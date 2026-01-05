#!/usr/bin/env node
/**
 * CLI entry point for ethernet-wifi-switcher
 * Reads facts from environment variables or stdin (JSON)
 * Outputs deterministic action lines compatible with shell test harness
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { evaluate, createInitialState, createDefaultConfig } from '../core/engine';
import { Facts, State, Config, Action } from '../core/types';

interface CliArgs {
  dryRun: boolean;
  stateFile: string;
  configFile?: string;
  factsFile?: string;
  help: boolean;
}

function parseArgs(): CliArgs {
  const args: CliArgs = {
    dryRun: process.env.DRY_RUN === '1',
    stateFile: process.env.STATE_FILE || '/tmp/eth-wifi-state',
    help: false
  };

  for (let i = 2; i < process.argv.length; i++) {
    const arg = process.argv[i];
    if (arg === '--dry-run' || arg === '-d') {
      args.dryRun = true;
    } else if (arg === '--state-file' || arg === '-s') {
      args.stateFile = process.argv[++i];
    } else if (arg === '--config-file' || arg === '-c') {
      args.configFile = process.argv[++i];
    } else if (arg === '--facts-file' || arg === '-f') {
      args.factsFile = process.argv[++i];
    } else if (arg === '--help' || arg === '-h') {
      args.help = true;
    }
  }

  return args;
}

function showHelp(): void {
  console.log(`
ethernet-wifi-switcher CLI

Usage: eth-wifi-switcher [options]

Options:
  --dry-run, -d          Enable dry-run mode (no actual actions)
  --state-file, -s PATH  Path to state file (default: /tmp/eth-wifi-state)
  --config-file, -c PATH Load config from JSON file
  --facts-file, -f PATH  Load facts from JSON file
  --help, -h             Show this help

Environment Variables (used if files not specified):
  DRY_RUN              Set to '1' for dry-run mode
  STATE_FILE           Path to state file
  STATE_DIR            Directory for state file (alternative to STATE_FILE)
  
  ETH_DEV              Ethernet interface name
  WIFI_DEV             WiFi interface name
  ETH_HAS_LINK         '1' if ethernet has link
  ETH_HAS_IP           '1' if ethernet has IP
  WIFI_IS_ON           '1' if WiFi is on
  ETH_HAS_INTERNET     '1' if ethernet has internet (optional)
  WIFI_HAS_INTERNET    '1' if WiFi has internet (optional)
  INTERFACE_PRIORITY   Comma-separated interface priority (optional)
  
  TIMEOUT              DHCP timeout in seconds (default: 7)
  CHECK_INTERNET       '1' to enable internet monitoring
  CHECK_METHOD         'gateway', 'ping', or 'curl' (default: gateway)
  CHECK_TARGET         Target for ping/curl checks
  CHECK_INTERVAL       Check interval in seconds (default: 30)
  LOG_ALL_CHECKS       '1' to log every check attempt

Output Format:
  ACTION: <action_type> [<params>]
  REASON: <reason_code>
  LOG: <message>
  STATE: <json>

Examples:
  # Using environment variables
  ETH_DEV=en5 WIFI_DEV=en0 ETH_HAS_LINK=1 ETH_HAS_IP=1 WIFI_IS_ON=1 eth-wifi-switcher

  # Using fixture files (for testing)
  eth-wifi-switcher --facts-file facts.json --config-file config.json

  # Dry-run mode
  DRY_RUN=1 ETH_DEV=en5 WIFI_DEV=en0 ETH_HAS_LINK=1 ETH_HAS_IP=0 eth-wifi-switcher
`);
}

async function loadFacts(factsFile?: string): Promise<Facts> {
  if (factsFile) {
    const content = await fs.readFile(factsFile, 'utf-8');
    return JSON.parse(content) as Facts;
  }

  // Load from environment variables
  const ethDev = process.env.ETH_DEV || 'eth0';
  const wifiDev = process.env.WIFI_DEV || 'wlan0';
  
  return {
    ethDev,
    wifiDev,
    ethHasLink: process.env.ETH_HAS_LINK === '1',
    ethHasIp: process.env.ETH_HAS_IP === '1',
    wifiIsOn: process.env.WIFI_IS_ON === '1',
    timestamp: Date.now(),
    ethHasInternet: process.env.ETH_HAS_INTERNET === '1' ? true : 
                    process.env.ETH_HAS_INTERNET === '0' ? false : undefined,
    wifiHasInternet: process.env.WIFI_HAS_INTERNET === '1' ? true :
                     process.env.WIFI_HAS_INTERNET === '0' ? false : undefined,
    interfacePriority: process.env.INTERFACE_PRIORITY || undefined
  };
}

async function loadConfig(configFile?: string): Promise<Config> {
  if (configFile) {
    const content = await fs.readFile(configFile, 'utf-8');
    return JSON.parse(content) as Config;
  }

  // Load from environment variables
  const defaults = createDefaultConfig();
  
  return {
    timeout: parseInt(process.env.TIMEOUT || '7', 10),
    checkInternet: process.env.CHECK_INTERNET === '1',
    checkMethod: (process.env.CHECK_METHOD as 'gateway' | 'ping' | 'curl') || defaults.checkMethod,
    checkTarget: process.env.CHECK_TARGET || undefined,
    checkInterval: parseInt(process.env.CHECK_INTERVAL || '30', 10),
    logAllChecks: process.env.LOG_ALL_CHECKS === '1',
    interfacePriority: process.env.INTERFACE_PRIORITY || undefined
  };
}

async function loadState(stateFile: string): Promise<State> {
  try {
    const content = await fs.readFile(stateFile, 'utf-8');
    return JSON.parse(content) as State;
  } catch {
    // State file doesn't exist or is invalid - return initial state
    return createInitialState();
  }
}

async function saveState(stateFile: string, state: State): Promise<void> {
  const dir = path.dirname(stateFile);
  try {
    await fs.mkdir(dir, { recursive: true });
  } catch {
    // Directory might already exist
  }
  await fs.writeFile(stateFile, JSON.stringify(state, null, 2), 'utf-8');
}

function formatAction(action: Action, dryRun: boolean): string {
  const prefix = dryRun ? '[DRY_RUN] ' : '';
  
  switch (action.type) {
    case 'ENABLE_WIFI':
      return `${prefix}ACTION: ENABLE_WIFI`;
    case 'DISABLE_WIFI':
      return `${prefix}ACTION: DISABLE_WIFI`;
    case 'WAIT_FOR_IP':
      return `${prefix}ACTION: WAIT_FOR_IP duration=${action.duration}`;
    case 'CHECK_INTERNET':
      return `${prefix}ACTION: CHECK_INTERNET interface=${action.interface}`;
    case 'FORCE_ROUTE':
      return `${prefix}ACTION: FORCE_ROUTE interface=${action.interface} gateway=${action.gateway}`;
    case 'LOG':
      return `${prefix}LOG: ${action.message}`;
    case 'NO_ACTION':
      return `${prefix}ACTION: NO_ACTION`;
    default:
      return `${prefix}ACTION: UNKNOWN`;
  }
}

async function main(): Promise<void> {
  const args = parseArgs();

  if (args.help) {
    showHelp();
    return;
  }

  try {
    // Load inputs
    const facts = await loadFacts(args.factsFile);
    const config = await loadConfig(args.configFile);
    const state = await loadState(args.stateFile);

    // Make decision
    const result = evaluate(facts, state, config);

    // Output actions
    for (const action of result.actions) {
      console.log(formatAction(action, args.dryRun));
    }

    // Output reason codes
    for (const reason of result.reasonCodes) {
      console.log(`REASON: ${reason}`);
    }

    // Save new state (unless dry-run)
    if (!args.dryRun) {
      await saveState(args.stateFile, result.newState);
    }

    // Output state as JSON for debugging (optional)
    if (process.env.DEBUG === '1') {
      console.log('STATE:', JSON.stringify(result.newState, null, 2));
    }

  } catch (error) {
    console.error('Error:', error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

// Only run if this is the main module
if (require.main === module) {
  main().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

export { main, loadFacts, loadConfig, loadState, saveState, formatAction };

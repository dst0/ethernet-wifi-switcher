/**
 * Unit tests for CLI functionality
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { loadFacts, loadConfig, formatAction } from '../cli';
import { Action } from '../../core/types';

describe('CLI', () => {
  const testDir = '/tmp/eth-wifi-cli-test';

  beforeEach(async () => {
    // Clean up test directory
    try {
      await fs.rm(testDir, { recursive: true });
    } catch (error) {
      // Directory might not exist
    }
    await fs.mkdir(testDir, { recursive: true });
  });

  afterEach(async () => {
    // Clean up
    try {
      await fs.rm(testDir, { recursive: true });
    } catch (error) {
      // Ignore cleanup errors
    }
  });

  describe('loadFacts', () => {
    test('should load facts from environment variables', async () => {
      process.env.ETH_DEV = 'en5';
      process.env.WIFI_DEV = 'en0';
      process.env.ETH_HAS_LINK = '1';
      process.env.ETH_HAS_IP = '1';
      process.env.WIFI_IS_ON = '0';

      const facts = await loadFacts();

      expect(facts.ethDev).toBe('en5');
      expect(facts.wifiDev).toBe('en0');
      expect(facts.ethHasLink).toBe(true);
      expect(facts.ethHasIp).toBe(true);
      expect(facts.wifiIsOn).toBe(false);
    });

    test('should use defaults when env vars not set', async () => {
      delete process.env.ETH_DEV;
      delete process.env.WIFI_DEV;
      delete process.env.ETH_HAS_LINK;
      delete process.env.ETH_HAS_IP;
      delete process.env.WIFI_IS_ON;

      const facts = await loadFacts();

      expect(facts.ethDev).toBe('eth0');
      expect(facts.wifiDev).toBe('wlan0');
      expect(facts.ethHasLink).toBe(false);
      expect(facts.ethHasIp).toBe(false);
      expect(facts.wifiIsOn).toBe(false);
    });

    test('should load facts from JSON file', async () => {
      const factsFile = path.join(testDir, 'facts.json');
      const factsData = {
        ethDev: 'eth1',
        wifiDev: 'wlan1',
        ethHasLink: true,
        ethHasIp: false,
        wifiIsOn: true,
        timestamp: 1234567890,
        ethHasInternet: false
      };

      await fs.writeFile(factsFile, JSON.stringify(factsData), 'utf-8');

      const facts = await loadFacts(factsFile);

      expect(facts.ethDev).toBe('eth1');
      expect(facts.wifiDev).toBe('wlan1');
      expect(facts.ethHasInternet).toBe(false);
    });

    test('should handle optional internet connectivity fields', async () => {
      process.env.ETH_HAS_INTERNET = '1';
      process.env.WIFI_HAS_INTERNET = '0';

      const facts = await loadFacts();

      expect(facts.ethHasInternet).toBe(true);
      expect(facts.wifiHasInternet).toBe(false);
    });
  });

  describe('loadConfig', () => {
    test('should load config from environment variables', async () => {
      process.env.TIMEOUT = '10';
      process.env.CHECK_INTERNET = '1';
      process.env.CHECK_METHOD = 'ping';
      process.env.CHECK_TARGET = '8.8.8.8';
      process.env.CHECK_INTERVAL = '60';
      process.env.LOG_ALL_CHECKS = '1';

      const config = await loadConfig();

      expect(config.timeout).toBe(10);
      expect(config.checkInternet).toBe(true);
      expect(config.checkMethod).toBe('ping');
      expect(config.checkTarget).toBe('8.8.8.8');
      expect(config.checkInterval).toBe(60);
      expect(config.logAllChecks).toBe(true);
    });

    test('should use defaults when env vars not set', async () => {
      delete process.env.TIMEOUT;
      delete process.env.CHECK_INTERNET;
      delete process.env.CHECK_METHOD;
      delete process.env.LOG_ALL_CHECKS;

      const config = await loadConfig();

      expect(config.timeout).toBe(7);
      expect(config.checkInternet).toBe(false);
      expect(config.checkMethod).toBe('gateway');
      expect(config.logAllChecks).toBe(false);
    });

    test('should load config from JSON file', async () => {
      const configFile = path.join(testDir, 'config.json');
      const configData = {
        timeout: 15,
        checkInternet: true,
        checkMethod: 'curl',
        checkTarget: 'http://1.1.1.1',
        checkInterval: 45,
        logAllChecks: false
      };

      await fs.writeFile(configFile, JSON.stringify(configData), 'utf-8');

      const config = await loadConfig(configFile);

      expect(config.timeout).toBe(15);
      expect(config.checkMethod).toBe('curl');
    });
  });

  describe('formatAction', () => {
    test('should format ENABLE_WIFI action', () => {
      const action: Action = {
        type: 'ENABLE_WIFI',
        reason: 'Ethernet disconnected'
      };

      const output = formatAction(action, false);

      expect(output).toBe('ACTION: ENABLE_WIFI');
    });

    test('should format DISABLE_WIFI action', () => {
      const action: Action = {
        type: 'DISABLE_WIFI',
        reason: 'Ethernet connected'
      };

      const output = formatAction(action, false);

      expect(output).toBe('ACTION: DISABLE_WIFI');
    });

    test('should format WAIT_FOR_IP action', () => {
      const action: Action = {
        type: 'WAIT_FOR_IP',
        duration: 5,
        reason: 'Waiting for DHCP'
      };

      const output = formatAction(action, false);

      expect(output).toBe('ACTION: WAIT_FOR_IP duration=5');
    });

    test('should format LOG action', () => {
      const action: Action = {
        type: 'LOG',
        message: 'Ethernet connected - WiFi disabled'
      };

      const output = formatAction(action, false);

      expect(output).toBe('LOG: Ethernet connected - WiFi disabled');
    });

    test('should prefix with DRY_RUN in dry-run mode', () => {
      const action: Action = {
        type: 'ENABLE_WIFI',
        reason: 'Test'
      };

      const output = formatAction(action, true);

      expect(output).toBe('[DRY_RUN] ACTION: ENABLE_WIFI');
    });

    test('should format NO_ACTION action', () => {
      const action: Action = {
        type: 'NO_ACTION',
        reason: 'Already in correct state'
      };

      const output = formatAction(action, false);

      expect(output).toBe('ACTION: NO_ACTION');
    });
  });
});

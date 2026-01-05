/**
 * Core types for the ethernet-wifi-switcher engine
 */

/**
 * Facts about the current network state (pure data, no side effects)
 */
export interface Facts {
  /** Primary ethernet interface name */
  ethDev: string;
  /** Primary WiFi interface name */
  wifiDev: string;
  /** Whether ethernet interface has link/carrier */
  ethHasLink: boolean;
  /** Whether ethernet interface has an IP address */
  ethHasIp: boolean;
  /** Whether WiFi is currently powered on */
  wifiIsOn: boolean;
  /** Current timestamp in milliseconds */
  timestamp: number;
  /** Optional: Whether ethernet has internet connectivity */
  ethHasInternet?: boolean;
  /** Optional: Whether WiFi has internet connectivity */
  wifiHasInternet?: boolean;
  /** Optional: Interface priority order (comma-separated) */
  interfacePriority?: string;
}

/**
 * Persistent state tracked across invocations
 */
export interface State {
  /** Last known ethernet connection state */
  lastEthState: 'connected' | 'disconnected';
  /** Timestamp of last ethernet state change */
  lastEthStateChange?: number;
  /** Last known internet check result for active interface */
  lastInternetCheckState?: 'success' | 'failed';
  /** Timestamp of last successful internet check */
  lastInternetCheckSuccess?: number;
}

/**
 * Configuration options
 */
export interface Config {
  /** Timeout in seconds to wait for IP acquisition */
  timeout: number;
  /** Whether to enable internet connectivity monitoring */
  checkInternet: boolean;
  /** Internet check method: 'gateway' | 'ping' | 'curl' */
  checkMethod: 'gateway' | 'ping' | 'curl';
  /** Target for ping/curl checks (e.g., '8.8.8.8', 'http://1.1.1.1') */
  checkTarget?: string;
  /** Interval in seconds between internet checks */
  checkInterval: number;
  /** Whether to log every check attempt (vs only state changes) */
  logAllChecks: boolean;
  /** Interface priority order (comma-separated, e.g., 'eth0,eth1,wlan0') */
  interfacePriority?: string;
}

/**
 * Actions to be performed (output of decision function)
 */
export type Action =
  | { type: 'ENABLE_WIFI'; reason: string }
  | { type: 'DISABLE_WIFI'; reason: string }
  | { type: 'WAIT_FOR_IP'; duration: number; reason: string }
  | { type: 'CHECK_INTERNET'; interface: string; reason: string }
  | { type: 'FORCE_ROUTE'; interface: string; gateway: string; reason: string }
  | { type: 'LOG'; message: string }
  | { type: 'NO_ACTION'; reason: string };

/**
 * Result of the decision function
 */
export interface DecisionResult {
  /** Actions to perform in order */
  actions: Action[];
  /** Human-readable reason codes explaining the decision */
  reasonCodes: string[];
  /** Updated state to persist */
  newState: State;
}

/**
 * Dependencies injected into the engine (for testing)
 */
export interface Dependencies {
  /** Get current timestamp in milliseconds */
  getCurrentTime: () => number;
  /** Execute a shell command and return output */
  exec: (command: string) => Promise<string>;
  /** Read a file */
  readFile: (path: string) => Promise<string>;
  /** Write a file */
  writeFile: (path: string, content: string) => Promise<void>;
}

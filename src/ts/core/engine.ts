/**
 * Pure decision engine for ethernet-wifi switching
 * No side effects - all decisions based on input facts, state, and config
 */

import { Facts, State, Config, DecisionResult, Action } from './types';

/**
 * Core decision function: evaluate facts and determine actions
 * This is a pure function with no side effects
 */
export function evaluate(
  facts: Facts,
  state: State,
  config: Config
): DecisionResult {
  const actions: Action[] = [];
  const reasonCodes: string[] = [];
  const newState: State = { ...state };

  // Determine current ethernet connectivity
  const ethConnected = facts.ethHasLink && facts.ethHasIp;
  
  // Check if ethernet state changed
  const ethStateChanged = 
    (ethConnected && state.lastEthState === 'disconnected') ||
    (!ethConnected && state.lastEthState === 'connected');

  // Update state if changed
  if (ethStateChanged) {
    newState.lastEthState = ethConnected ? 'connected' : 'disconnected';
    newState.lastEthStateChange = facts.timestamp;
  }

  // Decision tree
  if (ethConnected) {
    // Ethernet is connected
    
    if (config.checkInternet && facts.ethHasInternet === false) {
      // Ethernet has no internet - failover to WiFi
      reasonCodes.push('ETH_NO_INTERNET');
      
      if (!facts.wifiIsOn) {
        actions.push({
          type: 'ENABLE_WIFI',
          reason: 'Ethernet connected but no internet - enabling WiFi for failover'
        });
        actions.push({
          type: 'LOG',
          message: 'Ethernet has no internet connectivity - switching to WiFi'
        });
      } else {
        reasonCodes.push('WIFI_ALREADY_ON');
        actions.push({
          type: 'NO_ACTION',
          reason: 'WiFi already enabled for failover'
        });
      }
    } else {
      // Ethernet connected and has internet (or check disabled)
      reasonCodes.push('ETH_CONNECTED');
      
      if (facts.wifiIsOn) {
        actions.push({
          type: 'DISABLE_WIFI',
          reason: 'Ethernet connected with valid IP - disabling WiFi'
        });
        actions.push({
          type: 'LOG',
          message: 'Ethernet connected - WiFi disabled'
        });
      } else {
        reasonCodes.push('WIFI_ALREADY_OFF');
        actions.push({
          type: 'NO_ACTION',
          reason: 'Ethernet connected, WiFi already off'
        });
      }
    }
  } else if (facts.ethHasLink && !facts.ethHasIp) {
    // Ethernet has link but no IP - wait for DHCP
    reasonCodes.push('ETH_WAITING_FOR_IP');
    
    // Check if we've been waiting too long
    const waitTime = state.lastEthStateChange 
      ? (facts.timestamp - state.lastEthStateChange) / 1000 
      : 0;
    
    if (waitTime < config.timeout) {
      actions.push({
        type: 'WAIT_FOR_IP',
        duration: 1,
        reason: `Ethernet active but no IP yet (waited ${Math.floor(waitTime)}s/${config.timeout}s)`
      });
      actions.push({
        type: 'LOG',
        message: `Ethernet interface active but no IP yet, waiting... (${Math.floor(waitTime)}s)`
      });
    } else {
      // Timeout reached - enable WiFi
      reasonCodes.push('ETH_IP_TIMEOUT');
      
      if (!facts.wifiIsOn) {
        actions.push({
          type: 'ENABLE_WIFI',
          reason: `Ethernet failed to acquire IP after ${config.timeout}s - enabling WiFi`
        });
        actions.push({
          type: 'LOG',
          message: `Ethernet IP acquisition timeout (${config.timeout}s) - enabling WiFi`
        });
      }
    }
  } else {
    // Ethernet disconnected or no link
    reasonCodes.push('ETH_DISCONNECTED');
    
    if (!facts.wifiIsOn) {
      actions.push({
        type: 'ENABLE_WIFI',
        reason: 'Ethernet disconnected - enabling WiFi'
      });
      actions.push({
        type: 'LOG',
        message: 'Ethernet disconnected - WiFi enabled'
      });
    } else {
      reasonCodes.push('WIFI_ALREADY_ON');
      actions.push({
        type: 'NO_ACTION',
        reason: 'Ethernet disconnected, WiFi already on'
      });
    }
  }

  // Handle internet check state logging (if enabled)
  if (config.checkInternet && facts.ethHasInternet !== undefined) {
    const currentCheckState = facts.ethHasInternet ? 'success' : 'failed';
    const previousCheckState = state.lastInternetCheckState;
    
    if (!previousCheckState) {
      // First check - initialize state
      newState.lastInternetCheckState = currentCheckState;
      if (currentCheckState === 'success') {
        newState.lastInternetCheckSuccess = facts.timestamp;
      }
      
      if (config.logAllChecks) {
        actions.push({
          type: 'LOG',
          message: `Internet check: ${facts.ethDev} is ${currentCheckState === 'success' ? 'active and has internet' : 'not active'}`
        });
      }
    } else if (previousCheckState !== currentCheckState) {
      // State changed - always log
      newState.lastInternetCheckState = currentCheckState;
      if (currentCheckState === 'success') {
        newState.lastInternetCheckSuccess = facts.timestamp;
      }
      
      const message = currentCheckState === 'success'
        ? `Internet check: ${facts.ethDev} is now reachable (recovered from failure)`
        : `Internet check: ${facts.ethDev} is now unreachable (was working before)`;
      
      actions.push({
        type: 'LOG',
        message
      });
    } else if (config.logAllChecks) {
      // State unchanged but verbose logging enabled
      actions.push({
        type: 'LOG',
        message: `Internet check: ${config.checkMethod} check via ${facts.ethDev} ${currentCheckState === 'success' ? 'succeeded' : 'failed'}`
      });
    }
  }

  return {
    actions,
    reasonCodes,
    newState
  };
}

/**
 * Create initial state
 */
export function createInitialState(): State {
  return {
    lastEthState: 'disconnected'
  };
}

/**
 * Create default configuration
 */
export function createDefaultConfig(): Config {
  return {
    timeout: 7,
    checkInternet: false,
    checkMethod: 'gateway',
    checkInterval: 30,
    logAllChecks: false
  };
}

/**
 * Unit tests for the core decision engine
 */

import { evaluate, createInitialState, createDefaultConfig } from '../engine';
import { Facts, State, Config } from '../types';

describe('Core Engine', () => {
  let baseFacts: Facts;
  let baseState: State;
  let baseConfig: Config;
  const timestamp = Date.now();

  beforeEach(() => {
    baseFacts = {
      ethDev: 'en5',
      wifiDev: 'en0',
      ethHasLink: false,
      ethHasIp: false,
      wifiIsOn: true,
      timestamp
    };
    baseState = createInitialState();
    baseConfig = createDefaultConfig();
  });

  describe('Basic ethernet connect/disconnect', () => {
    test('should disable WiFi when ethernet connects', () => {
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true,
        wifiIsOn: true
      };

      const result = evaluate(facts, baseState, baseConfig);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'DISABLE_WIFI' })
      );
      expect(result.reasonCodes).toContain('ETH_CONNECTED');
      expect(result.newState.lastEthState).toBe('connected');
    });

    test('should enable WiFi when ethernet disconnects', () => {
      const state: State = {
        lastEthState: 'connected',
        lastEthStateChange: timestamp - 10000
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: false,
        ethHasIp: false,
        wifiIsOn: false
      };

      const result = evaluate(facts, state, baseConfig);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'ENABLE_WIFI' })
      );
      expect(result.reasonCodes).toContain('ETH_DISCONNECTED');
      expect(result.newState.lastEthState).toBe('disconnected');
    });

    test('should do nothing when ethernet connected and WiFi already off', () => {
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true,
        wifiIsOn: false
      };

      const result = evaluate(facts, baseState, baseConfig);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'NO_ACTION' })
      );
      expect(result.reasonCodes).toContain('WIFI_ALREADY_OFF');
    });

    test('should do nothing when ethernet disconnected and WiFi already on', () => {
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: false,
        ethHasIp: false,
        wifiIsOn: true
      };

      const result = evaluate(facts, baseState, baseConfig);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'NO_ACTION' })
      );
      expect(result.reasonCodes).toContain('WIFI_ALREADY_ON');
    });
  });

  describe('DHCP timeout handling', () => {
    test('should wait when ethernet has link but no IP', () => {
      const state: State = {
        lastEthState: 'disconnected',
        lastEthStateChange: timestamp - 2000 // 2 seconds ago
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: false,
        wifiIsOn: false,
        timestamp
      };

      const result = evaluate(facts, state, baseConfig);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'WAIT_FOR_IP' })
      );
      expect(result.reasonCodes).toContain('ETH_WAITING_FOR_IP');
    });

    test('should enable WiFi after DHCP timeout', () => {
      const state: State = {
        lastEthState: 'disconnected',
        lastEthStateChange: timestamp - 8000 // 8 seconds ago (timeout is 7)
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: false,
        wifiIsOn: false,
        timestamp
      };

      const result = evaluate(facts, state, baseConfig);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'ENABLE_WIFI' })
      );
      expect(result.reasonCodes).toContain('ETH_IP_TIMEOUT');
    });

    test('should respect custom timeout value', () => {
      const config: Config = {
        ...baseConfig,
        timeout: 10
      };
      const state: State = {
        lastEthState: 'disconnected',
        lastEthStateChange: timestamp - 8000 // 8 seconds ago
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: false,
        timestamp
      };

      const result = evaluate(facts, state, config);

      // Should still be waiting (8s < 10s timeout)
      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'WAIT_FOR_IP' })
      );
    });
  });

  describe('Internet connectivity monitoring', () => {
    test('should enable WiFi when ethernet has no internet', () => {
      const config: Config = {
        ...baseConfig,
        checkInternet: true
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true,
        ethHasInternet: false,
        wifiIsOn: false
      };

      const result = evaluate(facts, baseState, config);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'ENABLE_WIFI' })
      );
      expect(result.reasonCodes).toContain('ETH_NO_INTERNET');
    });

    test('should disable WiFi when ethernet has internet', () => {
      const config: Config = {
        ...baseConfig,
        checkInternet: true
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true,
        ethHasInternet: true,
        wifiIsOn: true
      };

      const result = evaluate(facts, baseState, config);

      expect(result.actions).toContainEqual(
        expect.objectContaining({ type: 'DISABLE_WIFI' })
      );
      expect(result.reasonCodes).toContain('ETH_CONNECTED');
    });

    test('should log internet state changes', () => {
      const config: Config = {
        ...baseConfig,
        checkInternet: true,
        logAllChecks: false
      };
      const state: State = {
        lastEthState: 'connected',
        lastInternetCheckState: 'success'
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true,
        ethHasInternet: false, // Changed from success to failed
        wifiIsOn: false
      };

      const result = evaluate(facts, state, config);

      const logActions = result.actions.filter(a => a.type === 'LOG');
      expect(logActions.length).toBeGreaterThan(0);
      expect(logActions.some(a => 
        'message' in a && a.message.includes('unreachable')
      )).toBe(true);
      expect(result.newState.lastInternetCheckState).toBe('failed');
    });

    test('should log all checks when verbose logging enabled', () => {
      const config: Config = {
        ...baseConfig,
        checkInternet: true,
        logAllChecks: true
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true,
        ethHasInternet: true,
        wifiIsOn: false
      };

      const result = evaluate(facts, baseState, config);

      const logActions = result.actions.filter(a => a.type === 'LOG');
      expect(logActions.length).toBeGreaterThan(0);
    });
  });

  describe('State management', () => {
    test('should track ethernet state changes', () => {
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true
      };

      const result = evaluate(facts, baseState, baseConfig);

      expect(result.newState.lastEthState).toBe('connected');
      expect(result.newState.lastEthStateChange).toBe(timestamp);
    });

    test('should not update state when no change', () => {
      const state: State = {
        lastEthState: 'connected',
        lastEthStateChange: timestamp - 5000
      };
      const facts: Facts = {
        ...baseFacts,
        ethHasLink: true,
        ethHasIp: true
      };

      const result = evaluate(facts, state, baseConfig);

      expect(result.newState.lastEthState).toBe('connected');
      expect(result.newState.lastEthStateChange).toBe(timestamp - 5000);
    });
  });

  describe('Factory functions', () => {
    test('createInitialState should return disconnected state', () => {
      const state = createInitialState();
      
      expect(state.lastEthState).toBe('disconnected');
      expect(state.lastEthStateChange).toBeUndefined();
    });

    test('createDefaultConfig should return sensible defaults', () => {
      const config = createDefaultConfig();
      
      expect(config.timeout).toBe(7);
      expect(config.checkInternet).toBe(false);
      expect(config.checkMethod).toBe('gateway');
      expect(config.checkInterval).toBe(30);
      expect(config.logAllChecks).toBe(false);
    });
  });
});

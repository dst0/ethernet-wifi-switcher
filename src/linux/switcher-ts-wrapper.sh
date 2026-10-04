#!/bin/sh
# Linux wrapper for TypeScript core engine
# This script collects network facts and calls the TS CLI for decision-making
set -eu

NODE="${NODE:-node}"

# Configuration (set by installer)
STATE_FILE="${STATE_FILE:-/tmp/eth-wifi-state}"
TIMEOUT="${TIMEOUT:-7}"
CHECK_INTERNET="${CHECK_INTERNET:-0}"
CHECK_METHOD="${CHECK_METHOD:-gateway}"
CHECK_TARGET="${CHECK_TARGET:-}"
LOG_ALL_CHECKS="${LOG_ALL_CHECKS:-0}"
INTERFACE_PRIORITY="${INTERFACE_PRIORITY:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"

# Path to TypeScript CLI (set by installer)
TS_CLI="${TS_CLI:-/opt/eth-wifi-auto/cli.js}"

# Backend library (set by installer)
BACKEND_LIB="${BACKEND_LIB:-/opt/eth-wifi-auto/lib/network-nmcli.sh}"

now(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(now)] $*"; }

# Load backend library for network operations
if [ -f "$BACKEND_LIB" ]; then
  . "$BACKEND_LIB"
else
  log "Error: Backend library not found at $BACKEND_LIB"
  exit 1
fi

# Collect facts about current network state
collect_facts(){
  # Get ethernet and WiFi device names
  if [ -n "$INTERFACE_PRIORITY" ]; then
    # Parse priority list
    ETH_DEV=$(echo "$INTERFACE_PRIORITY" | tr ',' '\n' | while read -r iface; do
      iface=$(echo "$iface" | xargs) # trim whitespace
      if [ -n "$iface" ] && is_ethernet_iface "$iface" 2>/dev/null; then
        echo "$iface"
        break
      fi
    done)
    WIFI_DEV=$(echo "$INTERFACE_PRIORITY" | tr ',' '\n' | while read -r iface; do
      iface=$(echo "$iface" | xargs) # trim whitespace
      if [ -n "$iface" ] && is_wifi_iface "$iface" 2>/dev/null; then
        echo "$iface"
        break
      fi
    done)
  else
    ETH_DEV=$(get_first_ethernet_iface)
    WIFI_DEV=$(get_first_wifi_iface)
  fi

  # Check if ethernet has link/connection
  eth_state=$(get_iface_state "$ETH_DEV" 2>/dev/null || echo "disconnected")
  if [ "$eth_state" = "connected" ] || [ "$eth_state" = "connecting" ]; then
    ETH_HAS_LINK=1
  else
    ETH_HAS_LINK=0
  fi

  # Check if ethernet has IP
  eth_ip=$(get_iface_ip "$ETH_DEV" 2>/dev/null || echo "")
  if [ -n "$eth_ip" ] && [ "$eth_state" = "connected" ]; then
    ETH_HAS_IP=1
  else
    ETH_HAS_IP=0
  fi

  # Check if WiFi is enabled
  if is_wifi_enabled 2>/dev/null; then
    WIFI_IS_ON=1
  else
    WIFI_IS_ON=0
  fi

  # Optional: Check internet connectivity
  if [ "$CHECK_INTERNET" = "1" ] && [ "$ETH_HAS_IP" = "1" ]; then
    case "$CHECK_METHOD" in
      gateway)
        # Ping gateway
        gateway=$(ip route show dev "$ETH_DEV" | grep default | awk '{print $3}' | head -1)
        if [ -n "$gateway" ] && ping -c 1 -W 3 "$gateway" >/dev/null 2>&1; then
          ETH_HAS_INTERNET=1
        else
          ETH_HAS_INTERNET=0
        fi
        ;;
      ping)
        # Ping external target
        target="${CHECK_TARGET:-8.8.8.8}"
        if ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
          ETH_HAS_INTERNET=1
        else
          ETH_HAS_INTERNET=0
        fi
        ;;
      curl)
        # HTTP check
        target="${CHECK_TARGET:-http://1.1.1.1}"
        if command -v curl >/dev/null 2>&1 && curl --connect-timeout 5 --max-time 10 -s -f "$target" >/dev/null 2>&1; then
          ETH_HAS_INTERNET=1
        else
          ETH_HAS_INTERNET=0
        fi
        ;;
      *)
        ETH_HAS_INTERNET=0
        ;;
    esac
  fi
}

# Apply actions returned by TS CLI
apply_action(){
  action_line="$1"
  
  # Parse action type
  action_type=$(echo "$action_line" | sed 's/\[DRY_RUN\] //' | sed 's/ACTION: //' | sed 's/LOG: //' | cut -d' ' -f1)
  
  case "$action_type" in
    ENABLE_WIFI)
      log "Enabling WiFi"
      enable_wifi
      ;;
    DISABLE_WIFI)
      log "Disabling WiFi"
      disable_wifi
      ;;
    WAIT_FOR_IP)
      # Extract duration
      duration=$(echo "$action_line" | sed 's/.*duration=//' | cut -d' ' -f1)
      sleep "${duration:-1}"
      ;;
    NO_ACTION)
      # Do nothing
      :
      ;;
    LOG)
      # Log lines are output as-is
      echo "$action_line"
      ;;
    *)
      # Unknown action or log line - just output it
      echo "$action_line"
      ;;
  esac
}

main(){
  # Collect current network facts
  collect_facts

  # Export facts as environment variables for TS CLI
  export ETH_DEV WIFI_DEV ETH_HAS_LINK ETH_HAS_IP WIFI_IS_ON
  export TIMEOUT CHECK_INTERNET CHECK_METHOD CHECK_TARGET
  export LOG_ALL_CHECKS INTERFACE_PRIORITY CHECK_INTERVAL
  export STATE_FILE DRY_RUN
  
  # Export optional internet check results
  if [ "$CHECK_INTERNET" = "1" ]; then
    export ETH_HAS_INTERNET
  fi

  # Call TypeScript CLI and capture output
  if [ -f "$TS_CLI" ]; then
    ts_output=$("$NODE" "$TS_CLI" 2>&1)
    ts_exit=$?
    
    if [ $ts_exit -ne 0 ]; then
      log "Error: TypeScript CLI failed with exit code $ts_exit"
      log "Output: $ts_output"
      return 1
    fi
    
    # Process each line of output
    echo "$ts_output" | while IFS= read -r line; do
      case "$line" in
        ACTION:*|LOG:*)
          if [ "${DRY_RUN:-0}" != "1" ]; then
            apply_action "$line"
          else
            # In dry-run mode, just print the action
            echo "$line"
          fi
          ;;
        REASON:*)
          # Reason codes are for debugging/logging
          if [ "${DEBUG:-0}" = "1" ]; then
            echo "$line"
          fi
          ;;
        *)
          # Other output (errors, debug info)
          echo "$line"
          ;;
      esac
    done
  else
    log "Error: TypeScript CLI not found at $TS_CLI"
    return 1
  fi
}

main "$@"

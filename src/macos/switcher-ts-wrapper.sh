#!/bin/sh
# macOS wrapper for TypeScript core engine
# This script collects network facts and calls the TS CLI for decision-making
set -eu

NETWORKSETUP="${NETWORKSETUP:-/usr/sbin/networksetup}"
IPCONFIG="${IPCONFIG:-/usr/sbin/ipconfig}"
IFCONFIG="${IFCONFIG:-/sbin/ifconfig}"
NODE="${NODE:-node}"

# Configuration (set by installer)
WIFI_DEV="${WIFI_DEV:-en0}"
ETH_DEV="${ETH_DEV:-en5}"
STATE_DIR="${STATE_DIR:-/tmp}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/eth-wifi-state}"
TIMEOUT="${TIMEOUT:-7}"
CHECK_INTERNET="${CHECK_INTERNET:-0}"
CHECK_METHOD="${CHECK_METHOD:-gateway}"
CHECK_TARGET="${CHECK_TARGET:-}"
LOG_ALL_CHECKS="${LOG_ALL_CHECKS:-0}"
INTERFACE_PRIORITY="${INTERFACE_PRIORITY:-}"
CHECK_INTERVAL="${CHECK_INTERVAL:-30}"

# Path to TypeScript CLI (set by installer)
TS_CLI="${TS_CLI:-/usr/local/share/eth-wifi-switcher/cli.js}"

now(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(now)] $*"; }

# Collect facts about current network state
collect_facts(){
  # Check if ethernet has link
  if "$IFCONFIG" "$ETH_DEV" 2>/dev/null | grep -q "status: active"; then
    ETH_HAS_LINK=1
  else
    ETH_HAS_LINK=0
  fi

  # Check if ethernet has IP
  if ip="$($IPCONFIG getifaddr "$ETH_DEV" 2>/dev/null)" && [ -n "$ip" ]; then
    ETH_HAS_IP=1
  else
    ETH_HAS_IP=0
  fi

  # Check if WiFi is on
  if "$NETWORKSETUP" -getairportpower "$WIFI_DEV" 2>/dev/null | grep -q "On"; then
    WIFI_IS_ON=1
  else
    WIFI_IS_ON=0
  fi

  # Optional: Check internet connectivity
  if [ "$CHECK_INTERNET" = "1" ]; then
    if command -v curl >/dev/null 2>&1; then
      if curl --interface "$ETH_DEV" --connect-timeout 5 --max-time 10 -s -f "http://1.1.1.1" >/dev/null 2>&1; then
        ETH_HAS_INTERNET=1
      else
        ETH_HAS_INTERNET=0
      fi
    else
      # Fall back to ping if curl not available
      if ping -c 1 -W 3000 "${CHECK_TARGET:-8.8.8.8}" >/dev/null 2>&1; then
        ETH_HAS_INTERNET=1
      else
        ETH_HAS_INTERNET=0
      fi
    fi
  fi
}

# Apply actions returned by TS CLI
apply_action(){
  action_line="$1"
  
  # Parse action type
  action_type=$(echo "$action_line" | sed 's/\[DRY_RUN\] //' | sed 's/ACTION: //' | sed 's/LOG: //' | cut -d' ' -f1)
  
  case "$action_type" in
    ENABLE_WIFI)
      log "Enabling WiFi ($WIFI_DEV)"
      "$NETWORKSETUP" -setairportpower "$WIFI_DEV" on
      ;;
    DISABLE_WIFI)
      log "Disabling WiFi ($WIFI_DEV)"
      "$NETWORKSETUP" -setairportpower "$WIFI_DEV" off
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

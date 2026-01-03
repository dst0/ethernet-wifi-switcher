#!/bin/sh
set -eu

NETWORKSETUP="/usr/sbin/networksetup"
DATE="/bin/date"
IPCONFIG="/usr/sbin/ipconfig"
IFCONFIG="/sbin/ifconfig"

# These will be set by the installer
WIFI_DEV="${WIFI_DEV:-en0}"
ETH_DEV="${ETH_DEV:-en5}"
STATE_FILE="${STATE_FILE:-/tmp/eth-wifi-state}"
TIMEOUT="${TIMEOUT:-7}"

now(){ "$DATE" "+%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(now)] $*"; }

read_last_state(){
  # If file doesn't exist or can't be read, treat as disconnected
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE" 2>/dev/null || echo "disconnected"
  else
    echo "disconnected"
  fi
}

write_state(){
  echo "$1" > "$STATE_FILE"
}

wifi_is_on(){
  "$NETWORKSETUP" -getairportpower "$WIFI_DEV" 2>/dev/null | grep -q "On"
}

set_wifi(){
  state="$1"
  "$NETWORKSETUP" -setairportpower "$WIFI_DEV" "$state"
}

eth_has_link(){
  # Check if interface is active (has carrier/link)
  "$IFCONFIG" "$ETH_DEV" 2>/dev/null | grep -q "status: active"
}

eth_is_up(){
  # Ethernet is up if interface has an IP address
  ip="$($IPCONFIG getifaddr "$ETH_DEV" 2>/dev/null || true)"
  [ -n "$ip" ]
}

eth_is_up_with_retry(){
  # Try immediate check
  if eth_is_up; then
    return 0
  fi

  # Check if interface has link but no IP yet
  if eth_has_link; then
    log "eth interface active but no IP yet, waiting..."
  fi

  # Poll every second until timeout
  elapsed=0
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))

    if eth_is_up; then
      log "eth acquired IP after ${elapsed}s"
      return 0
    fi
  done

  return 1
}

main(){
  last_state=$(read_last_state)

  # Quick check without retry
  if eth_is_up; then
    current_state="connected"
  else
    current_state="disconnected"
  fi

  # If state changed from connected to disconnected, enable wifi immediately
  if [ "$last_state" = "connected" ] && [ "$current_state" = "disconnected" ]; then
    log "eth disconnected, enabling wifi immediately"
    write_state "disconnected"
    if ! wifi_is_on; then
      set_wifi on
    fi
    return
  fi

  # If currently disconnected, use retry logic to wait for IP
  if [ "$last_state" = "disconnected" ] && [ "$current_state" = "disconnected" ]; then
    # Try with retry for new connection
    if eth_is_up_with_retry; then
      current_state="connected"
    fi
  fi

  # Update state and manage wifi
  write_state "$current_state"

  if [ "$current_state" = "connected" ]; then
    if wifi_is_on; then
      log "eth up, turning wifi off"
      set_wifi off
    fi
  else
    if ! wifi_is_on; then
      log "eth down, turning wifi on"
      set_wifi on
    fi
  fi
}

main "$@"

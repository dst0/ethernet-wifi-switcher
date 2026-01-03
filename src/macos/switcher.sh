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
CHECK_INTERNET="${CHECK_INTERNET:-0}"
CHECK_METHOD="${CHECK_METHOD:-gateway}"
CHECK_TARGET="${CHECK_TARGET:-}"

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

check_internet(){
  iface="$1"
  
  case "$CHECK_METHOD" in
    gateway)
      # Ping gateway - most reliable and safest method
      gateway=$(netstat -nr | grep "^default" | grep "$iface" | awk '{print $2}' | head -n 1)
      if [ -z "$gateway" ]; then
        log "No gateway found for $iface"
        return 1
      fi
      # Ping gateway with short timeout (macOS uses milliseconds for -W)
      if ping -c 1 -W 2000 "$gateway" >/dev/null 2>&1; then
        return 0
      fi
      ;;
    
    ping)
      # Ping domain/IP - requires CHECK_TARGET to be set
      if [ -z "$CHECK_TARGET" ]; then
        log "CHECK_TARGET not set for ping method"
        return 1
      fi
      if ping -c 1 -W 3000 "$CHECK_TARGET" >/dev/null 2>&1; then
        return 0
      fi
      ;;
    
    curl)
      # HTTP/HTTPS check using curl - may be blocked by providers
      if [ -z "$CHECK_TARGET" ]; then
        CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"
      fi
      if command -v curl >/dev/null 2>&1; then
        if curl --interface "$iface" --connect-timeout 5 --max-time 10 -s -f "$CHECK_TARGET" >/dev/null 2>&1; then
          return 0
        fi
      fi
      ;;
    
    *)
      log "Unknown CHECK_METHOD: $CHECK_METHOD"
      return 1
      ;;
  esac
  
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

  # If internet checking is enabled, verify actual internet connectivity
  if [ "$CHECK_INTERNET" = "1" ] && [ "$current_state" = "connected" ]; then
    log "Checking internet connectivity on $ETH_DEV..."
    if ! check_internet "$ETH_DEV"; then
      log "No internet on $ETH_DEV, treating as disconnected"
      current_state="disconnected"
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

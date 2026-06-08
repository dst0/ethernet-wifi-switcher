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

get_gateway(){
  dev="$1"
  # Try to get gateway from netstat for the specific interface
  gw=$(netstat -rn -f inet | grep -i "default" | grep "$dev" | awk '{print $2}' | head -n 1)
  if [ -z "$gw" ]; then
    # Fallback: if we have an IP, assume .1 on the same subnet
    ip="$($IPCONFIG getifaddr "$dev" 2>/dev/null || true)"
    if [ -n "$ip" ]; then
      gw=$(echo "$ip" | cut -d. -f1-3).1
    fi
  fi
  echo "$gw"
}

eth_has_internet(){
  if ! eth_is_up; then
    return 1
  fi

  gw=$(get_gateway "$ETH_DEV")
  if [ -z "$gw" ]; then
    log "could not determine gateway for $ETH_DEV"
    return 1
  fi

  # Canary host (Cloudflare DNS)
  canary="1.1.1.1"

  # Add a specific route to canary via Ethernet gateway
  # We use -host to only affect this specific IP
  if ! route add -host "$canary" "$gw" >/dev/null 2>&1; then
    # If adding route fails, it might already exist or gateway is unreachable
    # We try to delete and re-add just in case
    route delete -host "$canary" >/dev/null 2>&1 || true
    if ! route add -host "$canary" "$gw" >/dev/null 2>&1; then
      log "failed to add canary route to $canary via $gw"
      return 1
    fi
  fi

  # Test connectivity
  has_internet=1
  # -c 2: 2 packets, -W 2000: 2000ms timeout
  # We use || true to ensure set -e doesn't trip if ping fails
  if ping -c 2 -W 2000 "$canary" >/dev/null 2>&1; then
    has_internet=0
  fi

  # Cleanup route
  route delete -host "$canary" >/dev/null 2>&1 || true

  return $has_internet
}

eth_is_functional_with_retry(){
  # Try immediate check
  if eth_has_internet; then
    return 0
  fi

  # If eth has no link at all, don't bother retrying much
  if ! eth_has_link; then
    return 1
  fi

  log "eth has no internet, waiting for connection..."

  # Poll every second until timeout
  elapsed=0
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))

    if eth_has_internet; then
      log "eth acquired internet after ${elapsed}s"
      return 0
    fi
  done

  return 1
}

main(){
  last_state=$(read_last_state)

  # Check if ethernet is functional (has internet)
  if eth_has_internet; then
    current_state="connected"
  else
    current_state="disconnected"
  fi

  # If state changed from connected to disconnected, or if we are currently disconnected,
  # try a more thorough check with retries if ethernet seems to be present but not yet functional.
  if [ "$current_state" = "disconnected" ]; then
    if [ "$last_state" = "connected" ] || eth_has_link; then
       if eth_is_functional_with_retry; then
         current_state="connected"
       fi
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

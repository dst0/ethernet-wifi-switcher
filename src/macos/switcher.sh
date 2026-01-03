#!/bin/sh
set -eu

NETWORKSETUP="/usr/sbin/networksetup"
DATE="/bin/date"
IPCONFIG="/usr/sbin/ipconfig"

# These will be set by the installer
WIFI_DEV="${WIFI_DEV:-en0}"
ETH_DEV="${ETH_DEV:-en5}"

now(){ "$DATE" "+%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(now)] $*"; }

wifi_is_on(){
  "$NETWORKSETUP" -getairportpower "$WIFI_DEV" 2>/dev/null | grep -q "On"
}

set_wifi(){
  state="$1"
  "$NETWORKSETUP" -setairportpower "$WIFI_DEV" "$state"
}

eth_is_up(){
  # Ethernet is up if interface has an IP address
  ip="$($IPCONFIG getifaddr "$ETH_DEV" 2>/dev/null || true)"
  [ -n "$ip" ]
}

main(){
  if eth_is_up; then
    if wifi_is_on; then
      log "eth up, turning wifi off"
      set_wifi off
    else
      log "eth up, wifi already off"
    fi
  else
    if ! wifi_is_on; then
      log "eth down, turning wifi on"
      set_wifi on
    else
      log "eth down, wifi already on"
    fi
  fi
}

main "$@"

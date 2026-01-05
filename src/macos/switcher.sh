#!/bin/sh
set -eu

NETWORKSETUP="${NETWORKSETUP:-/usr/sbin/networksetup}"
DATE="${DATE:-/bin/date}"
IPCONFIG="${IPCONFIG:-/usr/sbin/ipconfig}"
IFCONFIG="${IFCONFIG:-/sbin/ifconfig}"

# These will be set by the installer
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
LAST_CHECK_STATE_FILE="${STATE_FILE}.last_check"

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

get_eth_dev() {
    # If INTERFACE_PRIORITY is set, use it; otherwise use ETH_DEV
    if [ -n "$INTERFACE_PRIORITY" ]; then
        # Parse priority list and return first available ethernet interface
        OLD_IFS="$IFS"
        IFS=','
        for iface in $INTERFACE_PRIORITY; do
            IFS="$OLD_IFS"
            iface=$(echo "$iface" | xargs) # trim whitespace
            if [ -n "$iface" ]; then
                # Check if interface exists and is ethernet type
                if "$IFCONFIG" "$iface" 2>/dev/null | grep -q "status:"; then
                    # Skip if it's the wifi interface
                    if [ "$iface" != "$WIFI_DEV" ]; then
                        echo "$iface"
                        return 0
                    fi
                fi
            fi
        done
        IFS="$OLD_IFS"
    fi
    # Default: use configured ETH_DEV
    echo "$ETH_DEV"
}

get_wifi_dev() {
    # If INTERFACE_PRIORITY is set, check it for wifi interfaces
    if [ -n "$INTERFACE_PRIORITY" ]; then
        # Parse priority list and return first available wifi interface
        OLD_IFS="$IFS"
        IFS=','
        for iface in $INTERFACE_PRIORITY; do
            IFS="$OLD_IFS"
            iface=$(echo "$iface" | xargs) # trim whitespace
            if [ -n "$iface" ]; then
                # Check if this is the configured wifi interface or looks like wifi
                if [ "$iface" = "$WIFI_DEV" ]; then
                    echo "$iface"
                    return 0
                fi
            fi
        done
        IFS="$OLD_IFS"
    fi
    # Default: use configured WIFI_DEV
    echo "$WIFI_DEV"
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

# Force default route through specified interface
# This is needed when both ethernet and WiFi have IPs but only one has internet
force_route_via_interface(){
  local iface="$1"
  local gateway

  gateway=$("$IPCONFIG" getoption "$iface" router 2>/dev/null || echo "")
  if [ -n "$gateway" ]; then
    log "   Forcing default route via gateway $gateway (interface $iface)"
    # Remove any existing default route
    route -n delete default >/dev/null 2>&1 || true
    # Add default route via this interface's gateway
    route -n add default "$gateway" >/dev/null 2>&1 || true
  else
    log "   Warning: Cannot force route - no gateway found for $iface"
  fi
}

check_internet(){
  iface="$1"
  is_active_interface="${2:-0}"  # 1 if this is the currently active interface, 0 if checking higher priority
  result=1

  # macOS Routing Solution:
  # When both interfaces have IPs, we manipulate routing tables to force traffic through
  # the interface with internet. This means we CANNOT rely on default routing for checks.
  # ALWAYS use curl with --interface binding to ensure we test the specific interface.

  # Check if curl is available
  if ! command -v curl >/dev/null 2>&1; then
    # curl not available - fall back to ping (may give false results if routing is forced)
    if [ "$is_active_interface" = "0" ]; then
      if [ "$LOG_ALL_CHECKS" = "1" ]; then
        log "Cannot reliably check inactive interface $iface: curl not available"
      fi
      return 1
    fi
    # For active interface without curl, try ping (less reliable)
    if ping -c 1 -W 3000 "${CHECK_TARGET:-8.8.8.8}" >/dev/null 2>&1; then
      result=0
    fi
    return $result
  fi

  # Use curl with interface binding for ALL checks (active and inactive)
  # This is the only reliable method when routing tables are manipulated
  check_target="http://1.1.1.1"
  if curl --interface "$iface" --connect-timeout 5 --max-time 10 -s -f "$check_target" >/dev/null 2>&1; then
    result=0
  fi

  if [ "$LOG_ALL_CHECKS" = "1" ]; then
    if [ $result -eq 0 ]; then
      if [ "$is_active_interface" = "1" ]; then
        log "Internet check: HTTP check via $iface succeeded (active interface)"
      else
        log "Internet check: HTTP check via $iface succeeded (inactive interface)"
      fi
    else
      if [ "$is_active_interface" = "1" ]; then
        log "Internet check: HTTP check via $iface failed (active interface)"
      else
        log "Internet check: HTTP check via $iface failed (inactive interface)"
      fi
    fi
  fi

  # Track state changes for active interface only
  if [ "$is_active_interface" = "1" ]; then
    # Log state changes (always logged regardless of LOG_ALL_CHECKS)
    last_check_state=$(cat "$LAST_CHECK_STATE_FILE" 2>/dev/null || echo "")
    current_check_state="success"
    if [ $result -ne 0 ]; then
      current_check_state="failed"
    fi

    if [ -z "$last_check_state" ]; then
      # First run - initialize state with specific message based on result
      if [ "$current_check_state" = "success" ]; then
        log "Internet check: $iface is active and has internet"
      else
        log "Internet check: $iface connection is not active"
      fi
      echo "$current_check_state" > "$LAST_CHECK_STATE_FILE"
    elif [ "$last_check_state" != "$current_check_state" ]; then
      # State changed - log the transition
      if [ "$current_check_state" = "success" ]; then
        log "Internet check: $iface is now reachable (recovered from failure)"
      else
        log "Internet check: $iface is now unreachable (was working before)"
      fi
      echo "$current_check_state" > "$LAST_CHECK_STATE_FILE"
    fi
  fi

  return $result
}

ensure_wifi_on_and_wait(){
  # This function assumes we are operating on the configured WIFI_DEV
  # It turns it on and waits for an IP address

  if ! wifi_is_on; then
    log "  Enabling WiFi ($WIFI_DEV) for failover check..."
    set_wifi on

    # Wait for IP address acquisition (up to 15 seconds)
    log "  Waiting for WiFi to connect and acquire IP address..."

    wait_retries=0
    max_wait_retries=15
    while [ $wait_retries -lt $max_wait_retries ]; do
       wifi_ip=$("$IPCONFIG" getifaddr "$WIFI_DEV" 2>/dev/null || true)
       if [ -n "$wifi_ip" ]; then
           log "  ✓ WiFi acquired IP address: $wifi_ip (after ${wait_retries}s)"
           break
       fi
       sleep 1
       wait_retries=$((wait_retries + 1))
    done

    # Check if we timed out
    if [ $wait_retries -eq $max_wait_retries ]; then
      log "  ⚠️  WiFi enabled but no IP address after ${max_wait_retries}s (not connected to network?)"
    fi
  fi
}

# Single iteration of the switcher logic.
# This is the orchestration entrypoint that tests can call to validate the real behavior.
#
# Returns:
#   0 always (decision is communicated via state file + wifi toggles + logs)
# Side-effects:
#   - may call networksetup/ipconfig/ifconfig/ping/curl
#   - may write state files
switcher_tick(){
  # Get current active interfaces based on priority
  ACTIVE_ETH_DEV=$(get_eth_dev)
  ACTIVE_WIFI_DEV=$(get_wifi_dev)

  last_state=$(read_last_state)

  # Determine current active interface (the one we're currently using)
  active_iface=""
  active_type=""
  wifi_on=$(wifi_is_on && echo "yes" || echo "no")

  # Check ethernet first (higher priority)
  if eth_is_up; then
    active_iface="$ACTIVE_ETH_DEV"
    active_type="ethernet"
  elif [ "$wifi_on" = "yes" ]; then
    # Check if wifi has IP address
    wifi_ip=$("$IPCONFIG" getifaddr "$ACTIVE_WIFI_DEV" 2>/dev/null || true)
    if [ -n "$wifi_ip" ]; then
      active_iface="$ACTIVE_WIFI_DEV"
      active_type="wifi"
    fi
  fi

  # If internet checking is enabled, validate the ACTIVE connection
  if [ "$CHECK_INTERNET" = "1" ] && [ -n "$active_iface" ]; then
    active_has_internet=0
    if [ "$LOG_ALL_CHECKS" = "1" ]; then
      log "Checking internet on active interface: $active_iface ($active_type)"
    fi

    if check_internet "$active_iface" 1; then  # 1 = is active interface
      active_has_internet=1
      if [ "$LOG_ALL_CHECKS" = "1" ]; then
        log "✓ Active interface $active_iface has internet"
      fi
    fi

    # Always check higher priority interfaces (whether active has internet or not)
    found_higher_priority=""
    found_higher_type=""
    if [ -n "$INTERFACE_PRIORITY" ]; then
      # Find position of active interface in priority list
      active_position=0
      position=0
      OLD_IFS="$IFS"
      IFS=','
      for iface in $INTERFACE_PRIORITY; do
        position=$((position + 1))
        iface=$(echo "$iface" | xargs)
        if [ "$iface" = "$active_iface" ]; then
          active_position=$position
          break
        fi
      done
      IFS="$OLD_IFS"

      # Check all HIGHER priority interfaces
      if [ $active_position -gt 1 ]; then
        if [ "$LOG_ALL_CHECKS" = "1" ]; then
          log "Checking higher priority interfaces for recovery..."
        fi

        position=0
        OLD_IFS="$IFS"
        IFS=','
        for iface in $INTERFACE_PRIORITY; do
          IFS="$OLD_IFS"
          position=$((position + 1))
          iface=$(echo "$iface" | xargs)

          # Only check interfaces with higher priority (lower position number)
          if [ $position -ge $active_position ]; then
            break
          fi

          if [ -z "$iface" ]; then
            continue
          fi

          # If this is the WiFi interface and it's off, turn it on to check
          if [ "$iface" = "$ACTIVE_WIFI_DEV" ] && ! wifi_is_on; then
            ensure_wifi_on_and_wait
          fi

          # Check if interface has IP address (is connected)
          iface_ip=$("$IPCONFIG" getifaddr "$iface" 2>/dev/null || true)
          if [ -n "$iface_ip" ]; then
            if [ "$LOG_ALL_CHECKS" = "1" ]; then
              log "  Checking $iface..."
            fi
            if check_internet "$iface" 0; then  # 0 = inactive interface, uses curl
              log "✓ Higher priority interface $iface has internet, switching..."
              found_higher_priority="$iface"
              if [ "$iface" = "$ACTIVE_WIFI_DEV" ]; then
                found_higher_type="wifi"
              else
                found_higher_type="ethernet"
              fi
              break
            else
              if [ "$LOG_ALL_CHECKS" = "1" ]; then
                log "  No internet on $iface"
              fi
            fi
          else
            if [ "$LOG_ALL_CHECKS" = "1" ]; then
              log "  Interface $iface has no IP address"
            fi
          fi
        done
        IFS="$OLD_IFS"
      fi

      # If higher priority interface found, switch to it
      if [ -n "$found_higher_priority" ]; then
        if [ "$found_higher_type" = "ethernet" ]; then
          log "→ Switching to Ethernet ($found_higher_priority)"
          write_state "connected"
          force_route_via_interface "$found_higher_priority"
          if wifi_is_on; then
            set_wifi off
          fi
        elif [ "$found_higher_type" = "wifi" ]; then
          log "→ Switching to WiFi ($found_higher_priority)"
          write_state "disconnected"
          if ! wifi_is_on; then
            set_wifi on
          fi
          force_route_via_interface "$found_higher_priority"
        fi
        return 0
      fi
    fi

    # If active interface has internet and no higher priority available, we're done
    if [ $active_has_internet -eq 1 ]; then
      # Ensure WiFi state matches the active interface type
      if [ "$active_type" = "ethernet" ]; then
        write_state "connected"
        if wifi_is_on; then
          log "eth up with internet, turning wifi off"
          set_wifi off
        fi
      elif [ "$active_type" = "wifi" ]; then
        write_state "disconnected"
        # WiFi should be on (it is, since it's active)
      fi
      return 0
    fi

    # Active interface has NO internet and no higher priority works - try lower priority
    log "⚠️  Active interface $active_iface has NO internet, searching for alternatives..."
    found_working_iface=""
    found_working_type=""

    if [ -n "$INTERFACE_PRIORITY" ]; then
      # Try all interfaces in priority order
      OLD_IFS="$IFS"
      IFS=','
      for iface in $INTERFACE_PRIORITY; do
        IFS="$OLD_IFS"
        iface=$(echo "$iface" | xargs)
        if [ -z "$iface" ] || [ "$iface" = "$active_iface" ]; then
          log "479 line"
          continue
        fi

        # Skip if this was the higher priority we already checked
        if [ "$iface" = "$found_higher_priority" ]; then
          log "485 line"
          continue
        fi

        # If this is the WiFi interface and it's off, turn it on to check
        if [ "$iface" = "$ACTIVE_WIFI_DEV" ] && ! wifi_is_on; then
          log "491 line"
          ensure_wifi_on_and_wait
        fi

        # Check if interface has IP address (is connected)
        iface_ip=$("$IPCONFIG" getifaddr "$iface" 2>/dev/null || true)
        if [ -n "$iface_ip" ]; then
          if [ "$LOG_ALL_CHECKS" = "1" ]; then
            log "  Checking $iface..."
          fi
          if check_internet "$iface" 0; then  # 0 = inactive interface, uses curl
            log "✓ Found working internet on $iface"
            found_working_iface="$iface"
            if [ "$iface" = "$ACTIVE_WIFI_DEV" ]; then
              found_working_type="wifi"
            else
              found_working_type="ethernet"
            fi
            break
          else
            log "  No internet on $iface"
          fi
        else
          if [ "$LOG_ALL_CHECKS" = "1" ]; then
            log "  Interface $iface has no IP address"
          fi
        fi
      done
      IFS="$OLD_IFS"
    else
      # No priority list - try ethernet then wifi
      if [ "$active_type" = "wifi" ] && eth_is_up; then
        if [ "$LOG_ALL_CHECKS" = "1" ]; then
          log "  Checking $ACTIVE_ETH_DEV (ethernet)..."
        fi
        if check_internet "$ACTIVE_ETH_DEV" 0; then  # 0 = inactive interface, uses curl
          log "✓ Found working internet on $ACTIVE_ETH_DEV"
          found_working_iface="$ACTIVE_ETH_DEV"
          found_working_type="ethernet"
        fi
      elif [ "$active_type" = "ethernet" ]; then
        # Current ethernet has no internet, try wifi
        if [ "$wifi_on" = "no" ]; then
          ensure_wifi_on_and_wait
        fi
        wifi_ip=$("$IPCONFIG" getifaddr "$ACTIVE_WIFI_DEV" 2>/dev/null || true)
        if [ -n "$wifi_ip" ]; then
          if [ "$LOG_ALL_CHECKS" = "1" ]; then
            log "  Checking $ACTIVE_WIFI_DEV (wifi)..."
          fi
          if check_internet "$ACTIVE_WIFI_DEV" 0; then  # 0 = inactive interface, uses curl
            log "✓ Found working internet on $ACTIVE_WIFI_DEV"
            found_working_iface="$ACTIVE_WIFI_DEV"
            found_working_type="wifi"
          fi
        fi
      fi
    fi

    # Switch to the working interface if found
    if [ -n "$found_working_iface" ]; then
      if [ "$found_working_type" = "ethernet" ]; then
        log "→ Switching to Ethernet ($found_working_iface)"
        write_state "connected"
        force_route_via_interface "$found_working_iface"
        if wifi_is_on; then
          set_wifi off
        fi
      elif [ "$found_working_type" = "wifi" ]; then
        log "→ Switching to WiFi ($found_working_iface)"
        write_state "disconnected"
        if ! wifi_is_on; then
          set_wifi on
        fi
        force_route_via_interface "$found_working_iface"
      fi
      if [ -n "$INTERFACE_PRIORITY" ]; then
        log "   Periodic checks will continue monitoring higher priority interfaces for recovery"
      fi
      return 0
    else
      log "⚠️  No interface with working internet found, keeping current: $active_iface"
      log "   Will continue checking all interfaces every ${CHECK_INTERVAL}s until internet is restored"
      # Keep current interface even without internet (better than nothing)
      return 0
    fi
  fi

  # Standard logic when not checking internet or internet is OK
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
    # If WiFi already has an IP, force route through it (ethernet route should auto-remove on disconnect)
    wifi_ip=$("$IPCONFIG" getifaddr "$ACTIVE_WIFI_DEV" 2>/dev/null || true)
    if [ -n "$wifi_ip" ]; then
      force_route_via_interface "$ACTIVE_WIFI_DEV"
    fi
    return 0
  fi

  # If state changed from disconnected to connected, verify internet before switching
  if [ "$last_state" = "disconnected" ] && [ "$current_state" = "connected" ]; then
    if [ "$CHECK_INTERNET" = "1" ]; then
      # When internet monitoring is enabled, verify ethernet has internet before switching
      log "eth connected (has IP), verifying internet before switching..."
      if check_internet "$ACTIVE_ETH_DEV" 1; then  # 1 = active interface
        log "eth up with internet, turning wifi off"
        write_state "connected"
        force_route_via_interface "$ACTIVE_ETH_DEV"
        if wifi_is_on; then
          set_wifi off
        fi
        return 0
      else
        # Ethernet has NO internet - don't use it, stay on WiFi
        log "⚠️  eth has IP but NO internet, staying on WiFi"
        write_state "disconnected"
        if ! wifi_is_on; then
          set_wifi on
        fi
        force_route_via_interface "$ACTIVE_WIFI_DEV"
        # Do NOT return here - let periodic check handle failover properly
      fi
    else
      # No internet checking - switch based on IP only (legacy behavior)
      log "eth connected, disabling wifi immediately"
      write_state "connected"
      force_route_via_interface "$ACTIVE_ETH_DEV"
      if wifi_is_on; then
        set_wifi off
      fi
      return 0
    fi
  fi

  # If currently disconnected, use retry logic to wait for IP
  if [ "$last_state" = "disconnected" ] && [ "$current_state" = "disconnected" ]; then
    # Try with retry for new connection
    if eth_is_up_with_retry; then
      current_state="connected"
      # State just changed, verify internet before disabling WiFi
      if [ "$CHECK_INTERNET" = "1" ]; then
        log "eth acquired IP after retry, verifying internet..."
        if check_internet "$ACTIVE_ETH_DEV" 1; then  # 1 = active interface
          log "eth has internet, disabling wifi"
          write_state "connected"
          force_route_via_interface "$ACTIVE_ETH_DEV"
          if wifi_is_on; then
            set_wifi off
          fi
          return 0
        else
          log "⚠️  eth has IP but NO internet, staying on WiFi"
          write_state "disconnected"
          if ! wifi_is_on; then
            set_wifi on
          fi
          force_route_via_interface "$ACTIVE_WIFI_DEV"
          # Do NOT return - let it continue to standard logic
        fi
      else
        # No internet checking - switch based on IP only (legacy behavior)
        log "eth acquired IP after retry, disabling wifi"
        write_state "connected"
        force_route_via_interface "$ACTIVE_ETH_DEV"
        if wifi_is_on; then
          set_wifi off
        fi
        return 0
      fi
    fi
  fi


  # Update state and manage wifi
  write_state "$current_state"

  if [ "$current_state" = "connected" ]; then
    if wifi_is_on; then
      log "eth up, turning wifi off"
      force_route_via_interface "$ACTIVE_ETH_DEV"
      set_wifi off
    fi
  else
    if ! wifi_is_on; then
      log "eth down, turning wifi on"
      set_wifi on
      force_route_via_interface "$ACTIVE_WIFI_DEV"
    fi
  fi

  return 0
}

main_loop(){
  while true; do
    switcher_tick
    sleep "$CHECK_INTERVAL"
  done
}

main(){
  # The macOS switcher doesn't currently accept meaningful CLI args.
  # Keep the signature for compatibility with prior behavior.
  main_loop
}

# Only execute main when run directly, not when sourced by tests.
# This avoids the need for tests to grep-filter out `main "$@"`.
if [ "${0}" = "${BASH_SOURCE:-$0}" ]; then
  main "$@"
fi

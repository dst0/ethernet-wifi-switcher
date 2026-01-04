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
LOG_CHECK_ATTEMPTS="${LOG_CHECK_ATTEMPTS:-0}"
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

check_internet(){
  iface="$1"
  is_active_interface="${2:-0}"  # 1 if this is the currently active interface, 0 if checking higher priority
  result=1

  # macOS Routing Solution:
  # For non-active interfaces, we ALWAYS use curl (regardless of CHECK_METHOD) because
  # macOS routing prevents reliable testing via ping/gateway on non-active interfaces.
  # For the active interface, we use the configured CHECK_METHOD.

  if [ "$is_active_interface" = "0" ]; then
    # Checking inactive interface - must use curl
    if ! command -v curl >/dev/null 2>&1; then
      # curl not available - cannot reliably test inactive interfaces on macOS
      if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
        log "Cannot check inactive interface $iface: curl not available (required for macOS)"
      fi
      return 1
    fi

    check_target="${CHECK_TARGET:-http://captive.apple.com/hotspot-detect.html}"
    if curl --interface "$iface" --connect-timeout 5 --max-time 10 -s -f "$check_target" >/dev/null 2>&1; then
      result=0
    fi
    if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
      if [ $result -eq 0 ]; then
        log "Internet check: HTTP check to $check_target via $iface succeeded (inactive interface)"
      else
        log "Internet check: HTTP check to $check_target via $iface failed (inactive interface)"
      fi
    fi
    # Don't log state changes for inactive interfaces - only active interface matters
    return $result
  fi

  # Active interface - use configured CHECK_METHOD

  case "$CHECK_METHOD" in
    gateway)
      # Ping gateway - Tests LOCAL connectivity to router (NOT actual internet)
      # Fast and reliable, but only verifies you can reach your router.
      # Does not verify that the router has internet access.
      gateway=$(netstat -nr | grep "^default" | grep "$iface" | awk '{print $2}' | head -n 1)
      if [ -z "$gateway" ]; then
        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
          log "No gateway found for $iface"
        fi
        return 1
      fi
      # Ping gateway with short timeout (macOS uses milliseconds for -W)
      if ping -c 1 -W 2000 "$gateway" >/dev/null 2>&1; then
        result=0
      fi
      if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
        if [ $result -eq 0 ]; then
          log "Internet check: gateway ping to $gateway via $iface succeeded"
        else
          log "Internet check: gateway ping to $gateway via $iface failed"
        fi
      fi
      ;;

    ping)
      # Ping domain/IP - For active interface, uses default routing (no binding needed)
      # Note: Non-active interfaces are checked with curl (handled earlier in this function)
      if [ -z "$CHECK_TARGET" ]; then
        log "CHECK_TARGET not set for ping method"
        return 1
      fi

      # For active interface, plain ping works fine (uses default route)
      # No need to bind to interface - macOS routing handles it automatically
      if ping -c 1 -W 3000 "$CHECK_TARGET" >/dev/null 2>&1; then
        result=0
      fi
      if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
        if [ $result -eq 0 ]; then
          log "Internet check: ping to $CHECK_TARGET via $iface succeeded"
        else
          log "Internet check: ping to $CHECK_TARGET via $iface failed"
        fi
      fi
      ;;

    curl)
      # HTTP/HTTPS check - Tests actual internet connectivity
      # RECOMMENDED for macOS multi-interface setups!
      # The --interface flag works correctly on non-active interfaces.
      if [ -z "$CHECK_TARGET" ]; then
        CHECK_TARGET="http://captive.apple.com/hotspot-detect.html"
      fi
      if command -v curl >/dev/null 2>&1; then
        if curl --interface "$iface" --connect-timeout 5 --max-time 10 -s -f "$CHECK_TARGET" >/dev/null 2>&1; then
          result=0
        fi
      fi
      if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
        if [ $result -eq 0 ]; then
          log "Internet check: HTTP check to $CHECK_TARGET via $iface succeeded"
        else
          log "Internet check: HTTP check to $CHECK_TARGET via $iface failed"
        fi
      fi
      ;;

    *)
      log "Unknown CHECK_METHOD: $CHECK_METHOD"
      return 1
      ;;
  esac

  # Log state changes (always logged regardless of LOG_CHECK_ATTEMPTS)
  last_check_state=$(cat "$LAST_CHECK_STATE_FILE" 2>/dev/null || echo "unknown")
  current_check_state="success"
  if [ $result -ne 0 ]; then
    current_check_state="failed"
  fi

  if [ "$last_check_state" != "$current_check_state" ]; then
    if [ "$current_check_state" = "success" ]; then
      log "Internet check: $iface is now reachable (recovered from failure)"
    else
      log "Internet check: $iface is now unreachable (was working before)"
    fi
    echo "$current_check_state" > "$LAST_CHECK_STATE_FILE"
  fi

  return $result
}

ensure_wifi_on_and_wait(){
  # This function assumes we are operating on the configured WIFI_DEV
  # It turns it on and waits for an IP address

  if ! wifi_is_on; then
    if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
      log "  Enabling WiFi ($WIFI_DEV) to check for internet..."
    fi
    set_wifi on

    # Wait for IP address acquisition (up to 15 seconds)
    if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
       log "  Waiting for IP address on $WIFI_DEV..."
    fi

    local wait_retries=0
    local max_wait_retries=15
    while [ $wait_retries -lt $max_wait_retries ]; do
       if [ -n "$("$IPCONFIG" getifaddr "$WIFI_DEV" 2>/dev/null || true)" ]; then
           break
       fi
       sleep 1
       wait_retries=$((wait_retries + 1))
    done
  fi
}

main(){
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
    if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
      log "Checking internet on active interface: $active_iface ($active_type)"
    fi

    if check_internet "$active_iface" 1; then  # 1 = is active interface
      active_has_internet=1
      if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
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
        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
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
            if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
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
              if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
                log "  No internet on $iface"
              fi
            fi
          else
            if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
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
          if wifi_is_on; then
            set_wifi off
          fi
        elif [ "$found_higher_type" = "wifi" ]; then
          log "→ Switching to WiFi ($found_higher_priority)"
          write_state "disconnected"
          if ! wifi_is_on; then
            set_wifi on
          fi
        fi
        return
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
      return
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
          continue
        fi

        # Skip if this was the higher priority we already checked
        if [ "$iface" = "$found_higher_priority" ]; then
          continue
        fi

        # If this is the WiFi interface and it's off, turn it on to check
        if [ "$iface" = "$ACTIVE_WIFI_DEV" ] && ! wifi_is_on; then
          ensure_wifi_on_and_wait
        fi

        # Check if interface has IP address (is connected)
        iface_ip=$("$IPCONFIG" getifaddr "$iface" 2>/dev/null || true)
        if [ -n "$iface_ip" ]; then
          if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
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
          if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
            log "  Interface $iface has no IP address"
          fi
        fi
      done
      IFS="$OLD_IFS"
    else
      # No priority list - try ethernet then wifi
      if [ "$active_type" = "wifi" ] && eth_is_up; then
        if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
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
          if [ "$LOG_CHECK_ATTEMPTS" = "1" ]; then
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
        if wifi_is_on; then
          set_wifi off
        fi
      elif [ "$found_working_type" = "wifi" ]; then
        log "→ Switching to WiFi ($found_working_iface)"
        write_state "disconnected"
        if ! wifi_is_on; then
          set_wifi on
        fi
      fi
      if [ -n "$INTERFACE_PRIORITY" ]; then
        log "   Periodic checks will continue monitoring higher priority interfaces for recovery"
      fi
      return
    else
      log "⚠️  No interface with working internet found, keeping current: $active_iface"
      log "   Will continue checking all interfaces every ${CHECK_INTERVAL}s until internet is restored"
      # Keep current interface even without internet (better than nothing)
      return
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

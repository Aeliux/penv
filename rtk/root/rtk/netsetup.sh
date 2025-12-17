#!/bin/sh
# netsetup.sh - automatic network setup script
#
# Behavior:
#  - Brings up loopback
#  - For each /sys/class/net/* (except lo) attempts to bring link up
#  - Waits for carrier (small timeout), then tries DHCP (udhcpc -> dhclient)
#  - Waits for DHCP lease (small timeout). If no lease, assigns a link-local 169.254.x.x
#  - Ensures there's at least one default route if DHCP provided a gateway
#  - If /etc/resolv.conf still empty, writes a safe fallback DNS (8.8.8.8)
#  - Prints summary (ip addr / ifconfig + routes)
#
# Intended for use in QEMU; user-visible special interfaces requiring extra steps are intentionally left alone.

# Configuration
BUSYBOX="/tmp/busybox"

# Setup command wrappers - check busybox first, then system
setup_cmd() {
  cmd="$1"
  if $BUSYBOX --list 2>/dev/null | grep -q "^${cmd}\$"; then
    eval "${cmd}='$BUSYBOX ${cmd}'"
  else
    cmd_path=$($BUSYBOX which "$cmd" 2>/dev/null || command -v "$cmd" 2>/dev/null)
    if [ -n "$cmd_path" ]; then
      eval "${cmd}='${cmd_path}'"
    else
      eval "${cmd}='$BUSYBOX ${cmd}'"
    fi
  fi
}

# Setup all commonly used commands
for cmd in cat echo printf date grep awk sed tr cut sleep basename ip ifconfig route which udhcpc dhclient; do
  setup_cmd "$cmd"
done

LOG="/dev/tty2"
exec >>"$LOG" 2>&1 || exec 1>/dev/null 2>&1

log() { $printf '%s %s\n' "$($date +%FT%T%z 2>/dev/null || $date)" "$*" ; }

# utilities detection
have() {
  cmd_to_check="$1"
  $BUSYBOX --list 2>/dev/null | $grep -q "^${cmd_to_check}\$" && return 0
  $which "$cmd_to_check" >/dev/null 2>&1
}

IP=0
IFCONFIG=0
UDHCPC=0
DHCLIENT=0

if have ip; then IP=1; fi
if have ifconfig && have route; then IFCONFIG=1; fi
if have udhcpc; then UDHCPC=1; fi
if have dhclient; then DHCLIENT=1; fi

log "Starting automatic network setup"
log "Tools: ip=$IP, ifconfig=$IFCONFIG, udhcpc=$UDHCPC, dhclient=$DHCLIENT"

# bring up loopback
if [ $IP -eq 1 ]; then
  log "Bringing up loopback (ip)"
  $ip link set lo up 2>/dev/null || true
else
  log "Bringing up loopback (ifconfig)"
  $ifconfig lo up 2>/dev/null || true
fi

# helpers
wait_for_carrier() {
  iface="$1"
  # check /sys/class/net/$iface/carrier if present, otherwise poll ip link state
  local tries=15
  if [ -r "/sys/class/net/$iface/carrier" ]; then
    while [ $tries -gt 0 ]; do
      c=$($cat /sys/class/net/$iface/carrier 2>/dev/null || $echo 0)
      if [ "$c" = "1" ]; then
        return 0
      fi
      tries=$((tries-1))
      $sleep 0.2
    done
    return 1
  else
    # fallback: check ip link state or ifconfig for UP
    while [ $tries -gt 0 ]; do
      if [ $IP -eq 1 ]; then
        state=$($ip -brief link show "$iface" 2>/dev/null | $awk '{print $2}' | $tr -d ,)
        [ "$state" = "UP" ] && return 0
      else
        # with ifconfig, presence of RUNNING typically indicates carrier
        $ifconfig "$iface" 2>/dev/null | $grep -q RUNNING >/dev/null 2>&1 && return 0
      fi
      tries=$((tries-1))
      $sleep 0.2
    done
    return 1
  fi
}

has_ip_addr() {
  iface="$1"
  if [ $IP -eq 1 ]; then
    $ip -4 addr show dev "$iface" | $grep -q "inet " && return 0
  else
    $ifconfig "$iface" 2>/dev/null | $grep -q "inet " && return 0
  fi
  return 1
}

assign_link_local() {
  iface="$1"
  # pick last 2 bytes of MAC for pseudo-random link-local
  mac=$($cat /sys/class/net/"$iface"/address 2>/dev/null | $tr -d ':' || $echo "")
  if [ -n "$mac" ]; then
    a=${mac%:*}
    b=${mac#*:}
    # fallback simple deterministic: 169.254.xx.yy from last 4 hex chars
    last4=$($echo "$mac" | $sed 's/://g' | $sed 's/.*\(....\)$/\1/')
    hi=$((0x${last4%??}))
    lo=$((0x${last4#??}))
    hi=$((hi % 254 + 1))
    lo=$((lo % 254 + 1))
    ipaddr="169.254.$hi.$lo"
  else
    ipaddr="169.254.42.42"
  fi

  if [ $IP -eq 1 ]; then
    log "Assigning link-local $ipaddr/16 to $iface"
    $ip addr add "$ipaddr/16" dev "$iface" 2>/dev/null || {
      log "ip addr add failed for $iface"
    }
  else
    log "Assigning link-local $ipaddr/16 to $iface (ifconfig fallback)"
    $ifconfig "$iface" "$ipaddr" netmask 255.255.0.0 2>/dev/null || {
      log "ifconfig assign failed for $iface"
    }
  fi
}

start_dhcp() {
  iface="$1"
  if [ $UDHCPC -eq 1 ]; then
    log "Starting udhcpc (BusyBox) on $iface"
    # -b: background, -i interface; let hooks update /etc/resolv.conf
    $udhcpc -i "$iface" -b >/dev/null 2>&1 || {
      log "udhcpc spawn failed for $iface"
    }
    return 0
  elif [ $DHCLIENT -eq 1 ]; then
    log "Starting dhclient on $iface"
    # dhclient may background by itself
    $dhclient "$iface" >/dev/null 2>&1 & disown || {
      log "dhclient spawn failed for $iface"
    }
    return 0
  fi
  return 1
}

# iterate interfaces
for dev in /sys/class/net/*; do
  iface=$($basename "$dev")
  [ "$iface" = "lo" ] && continue
  # skip virtual or bridge loopbacks? user said ignore complex ones - we try all
  log "Processing interface: $iface"

  # bring interface up
  if [ $IP -eq 1 ]; then
    $ip link set dev "$iface" up 2>/dev/null || log "ip link set up failed for $iface"
  else
    $ifconfig "$iface" up 2>/dev/null || log "ifconfig up failed for $iface"
  fi

  # wait for carrier (short)
  if wait_for_carrier "$iface"; then
    log "Carrier detected on $iface"
  else
    log "No carrier on $iface (continuing anyway)"
  fi

  # skip if it already has an IPv4 addr
  if has_ip_addr "$iface"; then
    log "$iface already has an IP; skipping DHCP"
    continue
  fi

  # start DHCP and wait for lease (simple wait)
  if start_dhcp "$iface"; then
    # wait up to N seconds for an address to appear
    tries=20   # ~10s
    while [ $tries -gt 0 ]; do
      if has_ip_addr "$iface"; then
        log "DHCP succeeded for $iface"
        break
      fi
      tries=$((tries-1))
      $sleep 0.5
    done

    if ! has_ip_addr "$iface"; then
      log "DHCP timed out for $iface"
      assign_link_local "$iface"
    fi
  else
    log "No DHCP client available; assigning link-local to $iface"
    assign_link_local "$iface"
  fi
done

# Ensure a default route exists; if none, attempt to pick one from interfaces
have_default=0
if [ $IP -eq 1 ]; then
  $ip route show | $grep -q '^default' && have_default=1
else
  $route -n | $awk '{if ($1=="0.0.0.0") {print; exit 0}}' >/dev/null && have_default=1
fi

if [ $have_default -eq 0 ]; then
  log "No default route set. Attempting to add one from DHCP-provided gateway if present."
  # try parse DHCP client leases for default gateway; udhcpc typically sets route already.
  # fallback: choose first interface with an IPv4 and add a route via .1 (best-effort)
  if [ $IP -eq 1 ]; then
    first_iface=$($ip -4 -o addr show scope global | $awk '{print $2; exit}')
  else
    first_iface=$($ifconfig 2>/dev/null | $awk '/inet /{print prev; exit} {prev=$1}' )
  fi

  if [ -n "$first_iface" ]; then
    # Make a conservative guess for gateway: last octet .1
    if [ $IP -eq 1 ]; then
      ipaddr=$($ip -4 -o addr show dev "$first_iface" | $awk '{print $4}' | $cut -d/ -f1)
      if [ -n "$ipaddr" ]; then
        gw=$($echo "$ipaddr" | $awk -F. '{printf "%d.%d.%d.1", $1,$2,$3}')
        log "Adding default route via $gw dev $first_iface (best-effort)"
        $ip route add default via "$gw" dev "$first_iface" 2>/dev/null || log "failed to add default route"
      fi
    else
      # ifconfig-based, try route add default gw
      ipaddr=$($ifconfig "$first_iface" 2>/dev/null | $awk '/inet /{print $2; exit}')
      if [ -n "$ipaddr" ]; then
        gw=$($echo "$ipaddr" | $awk -F. '{printf "%d.%d.%d.1", $1,$2,$3}')
        log "Adding default route via $gw dev $first_iface (best-effort)"
        $route add default gw "$gw" dev "$first_iface" 2>/dev/null || log "failed to add default route (ifconfig)"
      fi
    fi
  else
    log "No candidate interface found for default route"
  fi
fi

# Ensure /etc/resolv.conf exists / has content
if [ ! -s /etc/resolv.conf ]; then
  log "/etc/resolv.conf empty; writing fallback DNS (8.8.8.8)"
  $cat > /etc/resolv.conf <<EOF
# fallback resolv.conf provided by auto-net.sh
nameserver 8.8.8.8
EOF
fi

# print summary
log "Network setup summary:"
if [ $IP -eq 1 ]; then
  $ip -4 addr show
  $ip route show
else
  $ifconfig -a
  $route -n
fi

log "Network setup finished"

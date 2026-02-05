#!/bin/bash

# :: Save this script in your $HOME/.local/bin/vpn-killswitch.sh
VPN_INTERFACE="wg-PH-11"
VPN_SERVER_IP="188.214.125.162"
VPN_PORT="51820"

case "$1" in
enable)
  # :: Save current clean iptables state before modifying (only if clean state exists)
  if [ -f /tmp/iptables-clean-state.rules ]; then
    echo "✓ Using existing clean state as backup"
  else
    echo "⚠ No clean state found, saving current state"
    sudo iptables-save >/tmp/iptables-clean-state.rules
  fi

  # :: Flush OUTPUT chain only
  sudo iptables -F OUTPUT

  # :: Default deny
  sudo iptables -P OUTPUT DROP

  # :: Allow loopback
  sudo iptables -A OUTPUT -o lo -j ACCEPT

  # :: Allow established connections
  sudo iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # :: Allow VPN server connection
  sudo iptables -A OUTPUT -d $VPN_SERVER_IP -p udp --dport $VPN_PORT -j ACCEPT

  # :: Allow LAN
  sudo iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
  sudo iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT

  # :: Allow Docker networks
  sudo iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT # Docker default bridge range
  sudo iptables -A OUTPUT -o docker0 -j ACCEPT       # Docker bridge interface

  # :: Allow all Docker bridge interfaces (for custom networks)
  for iface in $(ip link show | grep 'br-' | awk -F: '{print $2}' | tr -d ' '); do
    sudo iptables -A OUTPUT -o $iface -j ACCEPT
  done

  # :: Allow VPN interface
  sudo iptables -A OUTPUT -o $VPN_INTERFACE -j ACCEPT

  echo "✓ Kill switch enabled (Docker allowed)"
  ;;
disable)
  echo "Disabling kill switch..."

  # :: Always flush OUTPUT chain and set policy to ACCEPT
  sudo iptables -F OUTPUT
  sudo iptables -P OUTPUT ACCEPT

  echo "✓ Cleared all OUTPUT rules"
  echo "✓ Set OUTPUT policy to ACCEPT"

  # :: Save clean state (without kill switch) - remove file first to avoid permission issues
  sudo rm -f /tmp/iptables-clean-state.rules
  sudo sh -c 'iptables-save > /tmp/iptables-clean-state.rules'

  echo "✓ Kill switch disabled"
  ;;

status)
  echo "Current OUTPUT policy:"
  sudo iptables -L OUTPUT -v -n
  echo ""
  echo "Active WireGuard interfaces:"
  sudo wg show interfaces
  ;;

*)
  echo "Usage: $0 {enable|disable|status}"
  exit 1
  ;;
esac

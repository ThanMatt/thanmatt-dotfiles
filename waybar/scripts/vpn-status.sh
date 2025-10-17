#!/bin/bash

if nmcli connection show --active | grep -q wireguard; then
  echo "󰌆 VPN"
else
  echo ""
fi

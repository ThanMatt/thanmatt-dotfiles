function VPN-status
    echo "WireGuard Status:"
    echo "================"
    sudo wg show
    echo ""
    echo "Kill Switch Status:"
    echo "==================="
    sudo ~/.local/bin/vpn-killswitch.sh status
end

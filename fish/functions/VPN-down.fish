function VPN-down
    # Get all active WireGuard interfaces
    set active (sudo wg show interfaces 2>/dev/null)

    if test -z "$active"
        echo "No active WireGuard connection found"
        return 1
    end

    # Disconnect each active interface
    for interface in $active
        echo "Disconnecting from $interface..."
        sudo wg-quick down $interface
    end

    echo ""
    echo "Disabling kill switch..."
    echo "================================"
    sudo ~/.local/bin/vpn-killswitch.sh disable

    echo ""
    echo "Restoring network connection..."
    sudo systemctl restart NetworkManager

    sleep 2

    echo "Network restored. You may need to reconnect to WiFi."
end

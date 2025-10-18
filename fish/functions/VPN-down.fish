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

    # Restart NetworkManager to restore normal network state
    echo "Restoring network connection..."
    sudo systemctl restart NetworkManager

    # Wait a moment for NetworkManager to initialize
    sleep 2

    echo "Network restored. You may need to reconnect to WiFi."
end

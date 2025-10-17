function VPN-down
    set active (sudo wg show | grep interface | awk '{print $2}')

    if test -z "$active"
        echo "No active WireGuard connection found"
        return 1
    end

    echo "Disconnecting from $active..."
    sudo wg-quick down $active
end

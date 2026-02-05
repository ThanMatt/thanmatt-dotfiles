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

    echo "Waiting for network to stabilize..."
    sleep 4

    echo ""
    echo "Restoring DNS settings..."
    echo "================================"
    # :: Clear resolvconf database first
    sudo resolvconf -d lo.* -f 2>/dev/null
    # :: Write DNS manually
    echo "nameserver 8.8.8.8
nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
    echo "✓ DNS restored (Google DNS: 8.8.8.8, Cloudflare: 1.1.1.1)"

    echo ""
    echo "✓ Network restored. You may need to reconnect to WiFi."
    echo ""
    echo "Testing internet connectivity..."
    if ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1
        echo "✓ Internet connectivity is working!"
        if ping -c 1 -W 3 archlinux.org > /dev/null 2>&1
            echo "✓ DNS resolution is working!"
        else
            echo "⚠ DNS resolution may need more time. Try: ping archlinux.org"
        end
    else
        echo "⚠ Could not reach internet. Try: ping 8.8.8.8"
    end
end

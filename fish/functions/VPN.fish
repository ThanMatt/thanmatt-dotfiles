function VPN
    set WIREGUARD_DIR /etc/wireguard

    # Check if WireGuard directory exists
    if not test -d $WIREGUARD_DIR
        echo "Error: Directory $WIREGUARD_DIR does not exist"
        echo "Please install WireGuard and configure your VPN profiles first"
        return 1
    end

    # Get list of .conf files (requires sudo to read /etc/wireguard)
    set configs (sudo find $WIREGUARD_DIR -maxdepth 1 -name "*.conf" 2>/dev/null)

    # Check if directory is empty or has no .conf files
    if test (count $configs) -eq 0
        echo "Error: No WireGuard configuration files found in $WIREGUARD_DIR"
        echo "Please add .conf files to $WIREGUARD_DIR first"
        return 1
    end

    # Extract server names (remove path and .conf extension)
    set servers
    for config in $configs
        set server (basename $config .conf)
        set servers $servers $server
    end

    # Display available servers
    echo "Available WireGuard VPN servers:"
    echo "================================"
    for i in (seq (count $servers))
        echo "$i. $servers[$i]"
    end
    echo ""

    # Prompt user to select a server
    read -P "Select a server (1-"(count $servers)"): " selection

    # ... existing validation ...

    set selected_server $servers[$selection]

    echo ""
    echo "🔒 Enabling kill switch..."
    echo "================================"
    sudo ~/.local/bin/vpn-killswitch.sh enable

    if test $status -ne 0
        echo "❌ Failed to enable kill switch"
        return 1
    end

    echo ""
    echo "✓ Kill switch active"
    echo "================================"

    echo ""
    echo "🔌 Connecting to $selected_server..."
    echo "================================"

    sudo wg-quick up $selected_server

    if test $status -eq 0
        echo ""
        echo "✓ Successfully connected to $selected_server"
        echo ""
        echo "Your connection is now protected by the kill switch"
    else
        echo ""
        echo "❌ Failed to connect to $selected_server"
        echo "Disabling kill switch..."
        sudo ~/.local/bin/vpn-killswitch.sh disable
        return 1
    end
end

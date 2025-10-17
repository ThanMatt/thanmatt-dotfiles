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

    # Validate input
    if not string match -qr '^[0-9]+$' -- $selection
        echo "Error: Invalid selection. Please enter a number"
        return 1
    end

    if test $selection -lt 1 -o $selection -gt (count $servers)
        echo "Error: Invalid selection. Please enter a number between 1 and "(count $servers)
        return 1
    end

    # Get selected server name
    set selected_server $servers[$selection]

    echo ""
    echo "Connecting to $selected_server..."
    echo "================================"

    # Connect to the selected VPN
    sudo wg-quick up $selected_server

    # Check if connection was successful
    if test $status -eq 0
        echo ""
        echo "Successfully connected to $selected_server"
    else
        echo ""
        echo "Error: Failed to connect to $selected_server"
        return 1
    end
end

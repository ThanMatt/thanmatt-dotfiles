function nightlight --description "toggle gammastep on/off"
    if systemctl --user is-active --quiet gammastep.service
        systemctl --user stop gammastep.service
        echo "Night light off"
    else
        systemctl --user start gammastep.service
        echo "Night light back on"
    end
end

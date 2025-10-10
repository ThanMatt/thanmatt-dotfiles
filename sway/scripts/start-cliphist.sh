# :: For clipboard management
#!/bin/bash
/usr/bin/wl-paste --type text --watch /usr/bin/cliphist store &
/usr/bin/wl-paste --type image --watch /usr/bin/cliphist store &

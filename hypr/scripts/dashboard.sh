#!/bin/bash
# Dashboard terminal launcher
# Opens a kitty window with cava, tty-clock, ncmpcpp, and nvim

# Check if dashboard is already running
if pgrep -f "kitty.*dashboard" > /dev/null; then
    # Kill existing dashboard
    pkill -f "kitty.*dashboard"
    exit 0
fi

# Launch dashboard kitty
kitty --title dashboard --config ~/.config/kitty/dashboard.conf \
    --directory ~ \
    -o background_opacity=0.85 \
    -o background_blur=1 \
    bash -c '
        # Split layout: cava left, clock+calendar right, ncmpcpp bottom-left, nvim bottom-right
        tty-clock -C 5 -c -f "%A, %B %d %Y" &
        sleep 0.5
        cava -p ~/.config/cava/config &
        sleep 0.5
        ncmpcpp &
        sleep 0.5
        nvim ~/dotfiles &
        wait
    '

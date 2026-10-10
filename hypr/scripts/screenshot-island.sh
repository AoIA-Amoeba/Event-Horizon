#!/usr/bin/env bash
set -euo pipefail

# Give the user a moment to hover the island before capturing the whole output.
sleep 2

if command -v xdg-user-dir >/dev/null 2>&1; then
    pictures_dir="$(xdg-user-dir PICTURES 2>/dev/null || true)"
fi
pictures_dir="${pictures_dir:-$HOME/Pictures}"
screenshots_dir="$pictures_dir/Screenshots"
mkdir -p -- "$screenshots_dir"

timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
output="$screenshots_dir/Island_$timestamp.png"
grim "$output"
printf 'Screenshot saved to %s\n' "$output"

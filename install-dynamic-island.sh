#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$REPO_DIR/quickshell/island/shell.qml"

if [[ ! -f "$SOURCE_FILE" ]]; then
    printf 'Island config not found: %s\n' "$SOURCE_FILE" >&2
    exit 1
fi

if [[ -z "${HOME:-}" ]]; then
    printf 'HOME is not set. Run this installer as your desktop user.\n' >&2
    exit 1
fi

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
if [[ "$CONFIG_HOME" != /* ]]; then
    printf 'XDG_CONFIG_HOME must be an absolute path.\n' >&2
    exit 1
fi

ISLAND_DIR="$CONFIG_HOME/quickshell/island"
ISLAND_FILE="$ISLAND_DIR/shell.qml"
HYPRLAND_FILE="$CONFIG_HOME/hypr/hyprland.conf"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

# These are the external commands/services used by the island. Quickshell,
# Hyprland, PipeWire, NetworkManager, and UPower provide its shell integrations.
PACKAGES=(hyprland quickshell curl networkmanager power-profiles-daemon wf-recorder libnotify upower pipewire)

if ! command -v pacman >/dev/null 2>&1; then
    printf 'This installer targets Arch Linux and needs pacman. Install these packages manually: %s\n' "${PACKAGES[*]}" >&2
else
    missing_packages=()
    for package in "${PACKAGES[@]}"; do
        if ! pacman -Q "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done

    if ((${#missing_packages[@]})); then
        printf 'Missing packages: %s\n' "${missing_packages[*]}"
        read -r -p 'Install them with pacman now? [Y/n] ' answer
        case "$answer" in
            [nN]|[nN][oO])
                printf 'Continuing without installing dependencies.\n'
                ;;
            *)
                if ((EUID == 0)); then
                    pacman -S --needed "${missing_packages[@]}"
                elif command -v sudo >/dev/null 2>&1; then
                    sudo pacman -S --needed "${missing_packages[@]}"
                else
                    printf 'Install these packages as root, then run this installer again: %s\n' "${missing_packages[*]}" >&2
                    exit 1
                fi
                ;;
        esac
    fi
fi

mkdir -p -- "$ISLAND_DIR"
if [[ -e "$ISLAND_FILE" || -L "$ISLAND_FILE" ]]; then
    if cmp -s -- "$SOURCE_FILE" "$ISLAND_FILE"; then
        printf 'Island config is already up to date.\n'
    else
        backup_file="$ISLAND_FILE.backup-$BACKUP_SUFFIX"
        cp -a -- "$ISLAND_FILE" "$backup_file"
        printf 'Backed up existing island config to %s\n' "$backup_file"
        temp_file="$(mktemp "$ISLAND_DIR/.shell.qml.XXXXXX")"
        trap '[[ -z "${temp_file:-}" ]] || rm -f -- "$temp_file"' EXIT
        install -m 0644 -- "$SOURCE_FILE" "$temp_file"
        mv -f -- "$temp_file" "$ISLAND_FILE"
        temp_file=""
    fi
else
    install -m 0644 -- "$SOURCE_FILE" "$ISLAND_FILE"
fi

if [[ -f "$HYPRLAND_FILE" ]]; then
    if grep -Eq '^[[:space:]]*exec-once[[:space:]]*=.*quickshell.*--path.*quickshell/island(/shell\.qml)?([[:space:]]|$)' "$HYPRLAND_FILE"; then
        printf 'Hyprland already has a Quickshell island startup command; leaving it as-is.\n'
    else
        backup_file="$HYPRLAND_FILE.backup-$BACKUP_SUFFIX"
        cp -a -- "$(realpath -- "$HYPRLAND_FILE")" "$backup_file"
        printf 'Backed up Hyprland config to %s\n' "$backup_file"
        {
            printf '\n# Dynamic island (installed by install-dynamic-island.sh)\n'
            printf 'exec-once = quickshell --no-duplicate --path "%s"\n' "$ISLAND_FILE"
        } >> "$HYPRLAND_FILE"
        printf 'Added island startup to %s\n' "$HYPRLAND_FILE"
    fi
else
    printf 'No Hyprland config found at %s; island startup was not added.\n' "$HYPRLAND_FILE"
fi

printf '\nInstalled the AI-free dynamic island to:\n  %s\n' "$ISLAND_FILE"
printf 'Log out and back in, or launch it now with:\n  quickshell --no-duplicate --path "%s"\n' "$ISLAND_FILE"

#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

################################################################################
# HAOS Kiosk Display
# Lightweight kiosk using Cage + Cog + WPE WebKit
################################################################################

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk ########"
bashio::log.info "$(date) [Version: $ADDON_VERSION]"
bashio::log.info "$(uname -a)"

################################################################################
# Clean up
################################################################################

cleanup() {
    local exit_code=$?
    bashio::log.info "Cleaning up and exiting..."
    jobs -p | xargs -r kill
    exit "$exit_code"
}

trap cleanup HUP INT QUIT ABRT TERM EXIT

################################################################################
# Configuration
################################################################################

load_config_var() {
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local MASK="${3:-}"

    local VALUE

    if declare -p "$VAR_NAME" >/dev/null 2>&1; then
        VALUE="${!VAR_NAME}"
    elif bashio::config.exists "${VAR_NAME,,}"; then
        VALUE="$(bashio::config "${VAR_NAME,,}")"
    else
        bashio::log.warning "Unknown config key: ${VAR_NAME,,}"
    fi

    if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
        VALUE="$DEFAULT"
    fi

    printf -v "$VAR_NAME" '%s' "$VALUE"
    export "$VAR_NAME"

    if [ -z "$MASK" ]; then
        bashio::log.info "$VAR_NAME=$VALUE"
    else
        bashio::log.info "$VAR_NAME=XXXXXX"
    fi
}

load_config_var HA_USERNAME
load_config_var HA_PASSWORD "" 1
load_config_var HA_URL "http://localhost:8123"
load_config_var HA_DASHBOARD ""
load_config_var SCREEN_TIMEOUT 600
load_config_var AUDIO_SINK auto
load_config_var REST_PORT 8080
load_config_var REST_IP "127.0.0.1"
load_config_var REST_BEARER_TOKEN "" 1
load_config_var COMMAND_WHITELIST "^$"
load_config_var DEBUG_MODE false

if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.error "Error: HA_USERNAME and HA_PASSWORD must be set"
    exit 1
fi

################################################################################
# Environment
################################################################################

export NO_AT_BRIDGE=1
export GTK_USE_PORTAL=0
export GIO_USE_VFS=local
export DBUS_SESSION_BUS_TIMEOUT=5000

# Avoid the DRI3 path that previously contributed to instability.
export LIBGL_DRI3_DISABLE=1

################################################################################
# Start DBus
################################################################################

DBUS_SESSION_BUS_ADDRESS=$(dbus-daemon --session --fork --print-address)

if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    bashio::log.warning "Failed to start dbus-daemon"
else
    bashio::log.info "DBus started"
    export DBUS_SESSION_BUS_ADDRESS
fi

################################################################################
# Start udev
################################################################################

bashio::log.info "Starting udev..."

if ! udevd --daemon || ! udevadm trigger; then
    bashio::log.warning "Failed to start udevd or trigger udev"
fi

udevadm settle --timeout=10

################################################################################
# Check DRM
################################################################################

bashio::log.info "DRM video cards:"

find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null |
    sed 's/^/  /'

selected_card=""

for status_path in /sys/class/drm/card[0-9]*-*/status; do
    [ -e "$status_path" ] || continue

    status=$(cat "$status_path")
    card_port=$(basename "$(dirname "$status_path")")
    card=${card_port%%-*}

    if [ "$status" = "connected" ] && [ -z "$selected_card" ]; then
        selected_card="$card"
        printf '  *%s %s\n' "$card_port" "$status"
    else
        printf '   %s %s\n' "$card_port" "$status"
    fi
done

if [ -z "$selected_card" ]; then
    bashio::log.error "No connected DRM display detected."
    exit 1
fi

bashio::log.info "Selected DRM device: /dev/dri/$selected_card"

################################################################################
# Build Home Assistant URL
################################################################################

DASHBOARD_URL="${HA_URL%/}"

if [ -n "$HA_DASHBOARD" ]; then
    DASHBOARD_URL="${DASHBOARD_URL}/${HA_DASHBOARD#/}"
fi

bashio::log.info "Home Assistant URL: $DASHBOARD_URL"

################################################################################
# Start REST server
################################################################################

bashio::log.info "Starting HAOSKiosk REST server..."

python3 -u /rest_server.py &

################################################################################
# Debug mode
################################################################################

if [ "$DEBUG_MODE" = true ]; then
    bashio::log.info "Debug mode enabled."
    bashio::log.info "Cage/Cog will NOT be started."

    exec sleep infinite
fi

################################################################################
# Start Cage + Cog
################################################################################

bashio::log.info "Starting lightweight kiosk browser..."
bashio::log.info "Browser: Cog"
bashio::log.info "Compositor: Cage"
bashio::log.info "URL: $DASHBOARD_URL"

# Cage provides a minimal Wayland kiosk compositor.
# Cog provides the WPE WebKit browser.

exec cage -- cog "$DASHBOARD_URL"

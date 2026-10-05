#!/usr/bin/with-contenv bashio
set -u

echo "."
printf '%*s\n' 80 '' | tr ' ' '#'
bashio::log.info "######## Starting HAOSKiosk ########"
bashio::log.info "$(date) [Version: $ADDON_VERSION]"
bashio::log.info "$(uname -a)"

TTY0_DELETED=""
ONBOARD_CONFIG_FILE="/config/onboard-settings.dconf"

cleanup() {
    local exit_code=$?
    bashio::log.info "Cleaning up and exiting..."

    if [ "${SAVE_ONSCREEN_CONFIG:-false}" = true ]; then
        dconf dump /org/onboard/ > "$ONBOARD_CONFIG_FILE" 2>/dev/null || true
    fi

    jobs -p | xargs -r kill 2>/dev/null || true

    if [ -n "$TTY0_DELETED" ]; then
        mknod -m 620 /dev/tty0 c 4 0 2>/dev/null || true
    fi

    rm -f /root/.local/share/luakit/cookies.db 2>/dev/null || true
    exit "$exit_code"
}

trap cleanup HUP INT QUIT ABRT TERM EXIT

BROWSER="luakit"
BROWSER_FLAGS=""

load_config_var() {
    local VAR_NAME="$1"
    local DEFAULT="${2:-}"
    local MASK="${3:-}"
    local VALUE=""

    if declare -p "$VAR_NAME" >/dev/null 2>&1; then
        VALUE="${!VAR_NAME}"
    elif bashio::config.exists "${VAR_NAME,,}"; then
        VALUE="$(bashio::config "${VAR_NAME,,}")"
    fi

    if [ "$VALUE" = "null" ] || [ -z "$VALUE" ]; then
        VALUE="$DEFAULT"
    fi

    printf -v "$VAR_NAME" '%s' "$VALUE"
    export "$VAR_NAME"

    if [ -n "$MASK" ]; then
        bashio::log.info "$VAR_NAME=XXXXXX"
    else
        bashio::log.info "$VAR_NAME=$VALUE"
    fi
}

load_config_var HA_USERNAME
load_config_var HA_PASSWORD "" 1
load_config_var HA_URL "http://localhost:8123"
load_config_var HA_DASHBOARD ""
load_config_var LOGIN_DELAY 1.0
load_config_var ZOOM_LEVEL 100
load_config_var BROWSER_REFRESH 600
load_config_var SCREEN_TIMEOUT 600
load_config_var OUTPUT_NUMBER 1
load_config_var DARK_MODE true
load_config_var HA_THEME ""
load_config_var HA_SIDEBAR "none"
load_config_var ROTATE_DISPLAY normal
load_config_var MAP_TOUCH_INPUTS true
load_config_var CURSOR_TIMEOUT 5
load_config_var KEYBOARD_LAYOUT us
load_config_var ONSCREEN_KEYBOARD false
load_config_var SAVE_ONSCREEN_CONFIG true
load_config_var XORG_CONF ""
load_config_var XORG_APPEND_REPLACE append
load_config_var AUDIO_SINK auto
load_config_var REST_PORT 8080
load_config_var REST_IP "127.0.0.1"
load_config_var REST_BEARER_TOKEN "" 1
load_config_var COMMAND_WHITELIST "^$"
load_config_var DEBUG_MODE false
load_config_var VNC_SERVER "" 1

if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    bashio::log.error "HA_USERNAME and HA_PASSWORD must be set"
    exit 1
fi

export DISPLAY=:0
export NO_AT_BRIDGE=1
export GTK_USE_PORTAL=0
export GIO_USE_VFS=local
export DBUS_SESSION_BUS_TIMEOUT=5000
export GTK_CSD=0

bashio::log.info "Starting DBus..."
DBUS_SESSION_BUS_ADDRESS="$(dbus-daemon --session --fork --print-address)"
export DBUS_SESSION_BUS_ADDRESS
echo "$DBUS_SESSION_BUS_ADDRESS" > /tmp/DBUS_SESSION_BUS_ADDRESS
bashio::log.info "DBus started"

if [ -e /dev/tty0 ]; then
    mount -o remount,rw /dev 2>/dev/null || true

    if rm -f /dev/tty0; then
        TTY0_DELETED=1
        bashio::log.info "Deleted /dev/tty0 for Xorg startup"
    fi
fi

bashio::log.info "Starting udev..."

udevd --daemon 2>/dev/null || true
udevadm trigger 2>/dev/null || true
udevadm settle --timeout=10 2>/dev/null || true

bashio::log.info "DRM video cards:"
find /dev/dri/ -maxdepth 1 -type c -name 'card[0-9]*' 2>/dev/null | sed 's/^/  /'

selected_card=""

for status_path in /sys/class/drm/card[0-9]*-*/status; do
    [ -e "$status_path" ] || continue

    status="$(cat "$status_path")"
    card_port="$(basename "$(dirname "$status_path")")"
    card="${card_port%%-*}"

    if [ "$status" = "connected" ] && [ -z "$selected_card" ]; then
        selected_card="$card"
        printf "  *"
    else
        printf "   "
    fi

    printf "%-25s%s\n" "$card_port" "$status"
done

if [ -z "$selected_card" ]; then
    bashio::log.error "No connected video card detected"
    exit 1
fi

bashio::log.info "Selected DRM device: /dev/dri/$selected_card"

rm -rf /tmp/.X*-lock

if [[ -n "$XORG_CONF" && "$XORG_APPEND_REPLACE" = "replace" ]]; then
    echo "$XORG_CONF" > /etc/X11/xorg.conf
else
    cp -a /etc/X11/xorg.conf.default /etc/X11/xorg.conf

    sed -i \
        "/Option[[:space:]]\+\"DRI\"[[:space:]]\+\"3\"/a\    Option \"kmsdev\" \"/dev/dri/$selected_card\"" \
        /etc/X11/xorg.conf

    if [ -n "$XORG_CONF" ] && [ "$XORG_APPEND_REPLACE" = "append" ]; then
        printf '\n#\n%s\n' "$XORG_CONF" >> /etc/X11/xorg.conf
    fi
fi

bashio::log.info "Starting X on DISPLAY=$DISPLAY..."

NOCURSOR=""
[ "$CURSOR_TIMEOUT" -lt 0 ] && NOCURSOR="-nocursor"

Xorg $NOCURSOR </dev/null 2>&1 &
XORG_PID=$!

XSTARTUP=30

for ((i=0; i<=XSTARTUP; i++)); do
    if xset q >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -n "$TTY0_DELETED" ]; then
    mknod -m 620 /dev/tty0 c 4 0 2>/dev/null || true
fi

if ! xset q >/dev/null 2>&1; then
    bashio::log.error "X server failed to start"
    exit 1
fi

bashio::log.info "X server started successfully"

if [ "$CURSOR_TIMEOUT" -gt 0 ]; then
    unclutter-xfixes \
        --start-hidden \
        --hide-on-touch \
        --fork \
        --timeout "$CURSOR_TIMEOUT" \
        2>/dev/null || true
fi

mkdir -p ~/.config/openbox

cp -a /etc/xdg/openbox/rc.xml ~/.config/openbox/rc.xml

openbox &
OPENBOX_PID=$!

sleep 1

if ! kill -0 "$OPENBOX_PID" 2>/dev/null; then
    bashio::log.error "Failed to start OpenBox"
    exit 1
fi

bashio::log.info "OpenBox window manager started successfully"

xset +dpms
xset s "$SCREEN_TIMEOUT"
xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"

readarray -t OUTPUTS < <(
    xrandr --query | awk '/ connected/ {print $1}'
)

if [ ${#OUTPUTS[@]} -eq 0 ]; then
    bashio::log.error "No connected HDMI outputs detected"
    exit 1
fi

bashio::log.info "Connected video outputs:"

for i in "${!OUTPUTS[@]}"; do
    bashio::log.info "  [$((i + 1))] ${OUTPUTS[$i]}"
done

if [ "$OUTPUT_NUMBER" -gt "${#OUTPUTS[@]}" ]; then
    OUTPUT_NUMBER="${#OUTPUTS[@]}"
fi

OUTPUT_NAME="${OUTPUTS[$((OUTPUT_NUMBER - 1))]}"

if [ "$ROTATE_DISPLAY" = "normal" ]; then
    xrandr --output "$OUTPUT_NAME" --primary --auto
else
    xrandr \
        --output "$OUTPUT_NAME" \
        --primary \
        --rotate "$ROTATE_DISPLAY"
fi

for OUTPUT in "${OUTPUTS[@]}"; do
    if [ "$OUTPUT" != "$OUTPUT_NAME" ]; then
        xrandr --output "$OUTPUT" --off
    fi
done

bashio::log.info "Selected output: $OUTPUT_NAME"

setxkbmap "$KEYBOARD_LAYOUT" 2>/dev/null || true

read -r SCREEN_WIDTH SCREEN_HEIGHT < <(
    xrandr --query --current |
    grep "^$OUTPUT_NAME " |
    sed -n "s/^$OUTPUT_NAME connected.* \([0-9]\+\)x\([0-9]\+\)+.*$/\1 \2/p"
)

bashio::log.info "Screen: Width=$SCREEN_WIDTH Height=$SCREEN_HEIGHT"

if [ "$MAP_TOUCH_INPUTS" = true ]; then
    while IFS= read -r id; do
        name="$(xinput list --name-only "$id" 2>/dev/null || true)"

        [[ "${name,,}" =~ touch|touchscreen|stylus ]] || continue

        xinput map-to-output "$id" "$OUTPUT_NAME" 2>/dev/null || true
    done < <(xinput list --id-only 2>/dev/null | sort -n)
fi

if [ "$ONSCREEN_KEYBOARD" = true ]; then
    onboard &
fi

bashio::log.info "Starting Mouse & Touch input parser..."

python3 -u /mouse_touch_inputs.py \
    -d 1 \
    -w "$COMMAND_WHITELIST" &

bashio::log.info "Starting HAOSKiosk REST server..."

python3 -u /rest_server.py &

if [ -n "$VNC_SERVER" ]; then
    x11vnc \
        -display :0 \
        -forever \
        -bg \
        -shared \
        -quiet &
fi

if [ "$DEBUG_MODE" != true ]; then

    sleep "$LOGIN_DELAY"

    DASHBOARD_URL="$HA_URL"

    if [ -n "$HA_DASHBOARD" ]; then
        DASHBOARD_URL="$DASHBOARD_URL/$HA_DASHBOARD"
    fi

    bashio::log.info "Launching Luakit: $DASHBOARD_URL"

    "$BROWSER" "$DASHBOARD_URL" &

    BROWSER_PID=$!

    bashio::log.info "Luakit started with PID $BROWSER_PID"

    wait "$BROWSER_PID"

    bashio::log.info "Luakit exited"
else
    bashio::log.info "DEBUG_MODE=true — Xorg/OpenBox running without browser"
    exec sleep infinity
fi

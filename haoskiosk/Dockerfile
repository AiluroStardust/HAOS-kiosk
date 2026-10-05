ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:3.21
FROM $BUILD_FROM

ARG BUILD_VERSION
ENV ADDON_VERSION=${BUILD_VERSION}

RUN apk update && apk add --no-cache \
    xorg-server \
    xf86-video-modesetting \
    mesa-dri-gallium \
    mesa-egl \
    mesa-gles \
    libdrm \
    xdotool \
    xinput \
    xrandr \
    xset \
    libxkbcommon \
    setxkbmap \
    xf86-input-libinput \
    libinput \
    libinput-udev \
    libevdev \
    udev \
    openbox \
    onboard \
    unclutter-xfixes \
    ttf-dejavu \
    bash \
    util-linux \
    patch \
    scrot \
    icu-data-full \
    py3-aiohttp \
    py3-xlib \
    pulseaudio-utils \
    x11vnc \
    dbus \
    dconf \
    gtk+3.0 \
    webkit2gtk-4.1 \
    luakit \
    && rm -rf /var/cache/apk/*

ENV HA_URL=http://localhost:8123

COPY translations/*.yaml /translations/
COPY run.sh /
RUN chmod a+x /run.sh

COPY mouse_touch_inputs.py gesture_commands.json /
COPY rest_server.py /

CMD ["/run.sh"]

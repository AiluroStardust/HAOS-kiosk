################################################################################
# Add-on: HAOS Kiosk Display (haoskiosk)
# File: Dockerfile
# Lightweight kiosk browser: Cog + WPE WebKit + Cage
################################################################################

ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:3.21
FROM $BUILD_FROM

ARG BUILD_VERSION
ENV ADDON_VERSION=${BUILD_VERSION}

#===============================================================================
##### Install lightweight graphics stack and kiosk browser
RUN apk update && apk add --no-cache \
     mesa-dri-gallium \
     mesa-egl \
     mesa-gles \
     libdrm \
     cage \
     cog \
     wpewebkit \
     libinput \
     libinput-udev \
     libevdev \
     udev \
     evtest \
     xf86-input-libinput \
     bash \
     util-linux \
     icu-data-full \
     py3-aiohttp \
     py3-xlib \
     pulseaudio-utils \
     ttf-dejavu \
     x11vnc \
   && rm -rf /var/cache/apk/*

#===============================================================================

##### Home Assistant kiosk URL
ENV HA_URL=http://localhost:8123

##### Copy translations and supporting files
COPY translations/*.yaml /translations/

COPY run.sh /
RUN chmod a+x /run.sh

COPY mouse_touch_inputs.py gesture_commands.json /
COPY rest_server.py /

#===============================================================================

CMD ["/run.sh"]

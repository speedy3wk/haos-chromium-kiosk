ARG BUILD_FROM=ghcr.io/home-assistant/aarch64-base:latest
FROM $BUILD_FROM

RUN apk add --no-cache \
    chromium \
    xorg-server \
    xf86-video-modesetting \
    xf86-input-libinput \
    libinput \
    libinput-udev \
    libevdev \
    udev \
    mesa-dri-gallium \
    mesa-egl \
    mesa-gles \
    libdrm \
    libxkbcommon \
    ttf-dejavu \
    util-linux \
    openbox \
    dbus \
    pulseaudio-utils \
    xdotool \
    xinput \
    xrandr \
    xset \
    unclutter-xfixes \
    setxkbmap \
    onboard \
    py3-xlib \
    patch \
    bash \
    x11vnc \
    bc \
    python3 \
    py3-aiohttp \
    py3-websockets \
    ca-certificates

COPY run.sh /
RUN chmod a+x /run.sh

COPY xorg.conf.default /etc/X11/

COPY translations /translations

COPY extension /haos-extension

ENV DISPLAY=:0

CMD ["/run.sh"]

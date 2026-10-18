# Multi-arch Home Assistant base image (Alpine). Pinned for reproducible builds;
# the Supervisor no longer passes BUILD_FROM (since 2026.04).
FROM ghcr.io/home-assistant/base:3.24

RUN apk add --no-cache \
    chromium \
    xorg-server \
    xf86-video-modesetting \
    xf86-input-libinput \
    libinput-udev \
    udev \
    mesa-dri-gallium \
    mesa-egl \
    mesa-gles \
    libva \
    libva-utils \
    mesa-va-gallium \
    font-dejavu \
    util-linux \
    openbox \
    dbus \
    pulseaudio-utils \
    xrandr \
    xset \
    unclutter-xfixes \
    python3

# Intel VA-API driver (iHD, Broadwell and newer) only exists for x86_64.
RUN if [ "$(apk --print-arch)" = "x86_64" ]; then \
      apk add --no-cache intel-media-driver; \
    fi

COPY run.sh /
RUN chmod a+x /run.sh

COPY xorg.conf.default /etc/X11/

COPY extension /haos-extension

CMD ["/run.sh"]

# proxmox-auto-install-assistant is a Debian package (Proxmox repo): it does
# not run on macOS, so the ISO is prepared in this container.
# Build: docker build --platform linux/amd64 -t pve-auto-install 00-bootstrap/
FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && curl -fsSL -o /usr/share/keyrings/proxmox-archive-keyring.gpg \
        https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/proxmox-archive-keyring.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
        > /etc/apt/sources.list.d/pve.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends proxmox-auto-install-assistant xorriso \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
ENTRYPOINT ["proxmox-auto-install-assistant"]

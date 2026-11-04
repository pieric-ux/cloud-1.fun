# node-exporter

Prometheus Node Exporter on every Linux host of the `linux` group (Proxmox
nodes, PBS, dhcp-dns, Prometheus, Grafana, qdevice03): official release
(checksum verified per architecture, amd64 / arm64 for the Raspberry Pi),
dedicated system user, systemd unit, listening on the host address, port
9100. From infra06; checked against production on 2026-11-04 (no change).

Variables: `defaults/main.yml` (version, checksums, port).

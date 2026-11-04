# prometheus

Prometheus server on `prometheus01`: official release (checksum verified),
promtool-validated configuration and alert rules, retention 15 days / 5 GB.
From infra06, aligned on production on 2026-11-04 (the live configuration
had been edited by hand: STP jobs added, node targets by name).

| Job | Targets |
|---|---|
| `node` | Node Exporter on the `linux` group (`prometheus_node_target` overrides `ansible_host`, e.g. dhcp-dns by name) |
| `pve` | pve-exporter (local) for pve01 / pve02 |
| `snmp` | snmp-exporter (local), `if_mib`: switches and NAS |
| `snmp_cisco_stp` / `snmp_bridge_stp` | STP state of the switches (`cisco_stp`, `bridge_stp` with the VLAN 240 community) |
| `pfsense` | pfSense, port 9100 |

Alert rules (`templates/alerts.yml.j2`): HostDown, HostDiskCritical,
HostDiskFull, HostMemoryLow, HostCpuHigh, HostRebootDetected, PveStorageFull,
SwitchInterfaceErrors. Sent to Alertmanager (local).

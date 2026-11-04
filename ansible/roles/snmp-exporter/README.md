# snmp-exporter

Prometheus SNMP exporter on `prometheus01` (official release, local only:
127.0.0.1:9116). `snmp.yml` is assembled from:

- the v2c auths: `rack_v2` (community `vault_snmp_community`) and the extra
  auths of `snmp_exporter_extra_auths` (`rack_v2_vlan240`: same community +
  `@240`, how Cisco serves the BRIDGE-MIB of VLAN 240);
- the modules of the official `snmp.yml` of the pinned version;
- `files/stp-modules.yml`: `cisco_stp` and `bridge_stp`, not in the official
  file (added by hand in production, kept here).

Checked on 2026-11-04: the assembled file has the same auths and the same
56 modules as the live one (only the order differs). From infra06.

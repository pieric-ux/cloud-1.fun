# network

`addressing.yml` is the **single source of the addressing of the rack**:

- DHCP and DNS of dhcp-dns are generated from it (role `dnsmasq`, layer 30):
  ranges and gateways per network, reservations by MAC (or by name for the
  k3s nodes), one DNS record per machine (FQDN + short name + aliases), one
  per web service pointing to the reverse proxy rproxy-int01;
- Terraform (`20-proxmox/locals.tf`) reads the guest addresses and the MGMT
  gateway from it for cloud-init.

**Add a VM**: one line in `hosts` (name, address), its `vm_<name>.tf` using
`local.host_ip["<name>"]`, then `make vms-plan` / `make vms-apply` and
`make dns-check` / `make dns-apply CONFIRM=yes`. A web service behind the
reverse proxy: one name in `services` (plus its site on rproxy-int01).

Migrated on 2026-11-04 from the hand-made `dnsmasq.conf` and `/etc/hosts`:
same DHCP configuration, same DNS answers except the intended changes (short
names for every machine, `mk7` no longer answering the address of sliver-c2,
gitea and captive-portal added; captive-portal removed again the same
day, a testing VM outside the infrastructure). `/etc/hosts` of dhcp-dns is no longer read by
dnsmasq (`no-hosts`) and holds only its local names.

# dnsmasq

DHCP and DNS of the rack on dhcp-dns, **generated from
`network/addressing.yml`**, the single source of the addressing (Terraform
reads the same file for the guest addresses).

- `/etc/dnsmasq.conf`: upstream DNS, domain, DHCP ranges and gateways per
  network, global options (DNS, NTP), reservations (by MAC, or by name for
  the k3s nodes); validated with `dnsmasq --test`, restart on change.
- `/etc/dnsmasq.hosts` (`addn-hosts`, `no-hosts`): one record per machine
  (FQDN + short name + aliases) and one per web service, pointing to the
  reverse proxy rproxy-int01; reload (SIGHUP) on change.
- `/etc/hosts` of dhcp-dns: local names only (localhost, its own name), the
  host resolves the rack through its own dnsmasq.

Add a machine: one line in `hosts`; a web service: one name in `services`;
then `make dns-check` and `make dns-apply CONFIRM=yes`.

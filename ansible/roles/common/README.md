# common

Base configuration of every VM (layer 30), Debian family and Alpine.

## What it does

| File | Action |
|---|---|
| `Debian.yml` / `Alpine.yml` | OS-specific tasks (Debian: apt upgrade `safe`, Ubuntu Pro nag services masked) |
| `packages.yml` | base packages (`common_packages`) |
| `timezone.yml` | timezone (`common_timezone`, Europe/Zurich) |
| `chrony.yml` | chrony with pfSense `10.1.255.2` as only NTP source |
| `motd.yml` | `/etc/motd` with the hostname and the role of the host |

OS-specific values in `vars/<distribution|os_family>.yml` (chrony service
name, leap seconds zone). Needs facts (`gather_facts` on).

## Variables

| Variable | Default | Where it is set |
|---|---|---|
| `common_timezone` | `Europe/Zurich` | defaults |
| `common_ntp_servers` | `[10.1.255.2]` | defaults |
| `common_packages` | curl, vim, git, htop, jq, python3, net-tools | defaults |
| `common_motd_role` | `unassigned` | one per group in `inventory/group_vars/<group>.yml` (dns, monitoring, rproxy...) |

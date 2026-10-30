# pve_config

Proxmox VE node configuration after an install: what a fresh node does not
have. **Checked against the live nodes on 2026-10-30** (`--check --diff`, no
real run yet): repos, system and iSCSI match production (only `Enabled: no`
→ `false` on pve01, same meaning). Cluster join and storages (`cluster.yml`,
`storage.yml`) are not imported by `main.yml` and not validated.

## Tasks

| File | What it does |
|---|---|
| `main.yml` | confirmation guard, then repos, system, iSCSI |
| `repos.yml` | enterprise / ceph repos disabled, `pve-no-subscription` (deb822) |
| `system.yml` | cluster nodes in `/etc/hosts` (no DNS during a rebuild), NTP on pfSense only |
| `iscsi.yml` | **recorded initiator IQN** (the NAS masking refuses any other), CHAP in `iscsid.conf`, multipath alias for the LUN |
| `storage.yml` | cluster-wide storages (`synology-iscsi`, `synology-lvm`, `synology-iso`), created only when missing, run once |
| `cluster.yml` | read-only cluster state + the **manual** re-join procedure (not automated yet: a wrong join breaks the cluster) |

Real run refused unless `pve_config_confirm=true`; the play runs one node at
a time (`serial: 1`).

## Variables

`group_vars/pve/vars.yml` (iSCSI target, LUN WWID, storages, cluster name,
qdevice), `host_vars/pveXX.yml` (`pve_iscsi_initiator_name`). The CHAP secret
(`vault_pve_iscsi_chap_password`) still has to be added to a vault.

## Not covered yet

PBS storage (fingerprint + API token in a vault) and the backup job,
datacenter options (migration network `10.1.230.0/30`), HA groups, qdevice
setup, users and ACL.

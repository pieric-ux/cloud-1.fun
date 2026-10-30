# pve_config

Proxmox VE node configuration after an install: what a fresh node does not
have. **Checked against the live nodes on 2026-10-30** (`--check --diff`, no
real run yet): everything matches production (only `Enabled: no` → `false`
on pve01, same meaning). The cluster join stays manual (`cluster.yml`, not
imported).

## Tasks

| File | What it does |
|---|---|
| `main.yml` | confirmation guard, then repos, system, iSCSI, then the cluster-wide files |
| `repos.yml` | enterprise / ceph repos disabled, `pve-no-subscription` (deb822) |
| `system.yml` | cluster nodes in `/etc/hosts` (no DNS during a rebuild), NTP on pfSense only |
| `iscsi.yml` | **recorded initiator IQN** (the NAS masking refuses any other), CHAP in `iscsid.conf`, multipath alias for the LUN |
| `datacenter.yml` | datacenter options (`datacenter.cfg`: keyboard, CRS, HA shutdown policy, migration network), only the differing keys set through `pvesh` |
| `storage.yml` | cluster-wide storages (Synology iSCSI / LVM / NFS, `pbs-store1`, `pbs-offsite`) created through `pvesh` when missing; vault secrets compared by checksum with `/etc/pve/priv/storage/` |
| `backup.yml` | backup jobs (`jobs.cfg`, daily vzdump to `pbs-store1`, PBS VM excluded) created when missing |
| `cluster.yml` | read-only cluster state + the **manual** re-join procedure (not automated yet: a wrong join breaks the cluster) |

Real run refused unless `pve_config_confirm=true`; the play runs one node at
a time (`serial: 1`).

## Variables

`group_vars/pve/vars.yml` (iSCSI target, LUN WWID, datacenter options,
storages, backup jobs, cluster name, qdevice), `host_vars/pveXX.yml`
(`pve_iscsi_initiator_name`). Secrets in `group_vars/pve/vault.yml`:

| Variable | Content |
|---|---|
| `vault_pve_iscsi_chap_password` | CHAP secret of the NAS target |
| `vault_pve_pbs_store1_token` | secret of the `pve@pbs!pve-cluster` token (`/etc/pve/priv/storage/pbs-store1.pw`) |
| `vault_pve_pbs_offsite_token` | secret of the `pve-restore@pbs!dr` token (`pbs-offsite.pw`) |
| `vault_pve_pbs_offsite_encryption_key` | encryption key of the offsite backups (`pbs-offsite.enc`, as a block scalar): **without it no offsite backup can be restored** |

Cluster-wide objects are created only when missing and never modified: a
drift on an existing storage or job is not corrected. On a rebuilt cluster,
`pbs-store1` can only be added once the PBS VM is back (the API checks the
datastore).

## Not covered yet

HA resources and rules, qdevice setup, users / tokens / ACL (`monitoring@pve`,
`packer@pve`, the future `terraform@pve`).

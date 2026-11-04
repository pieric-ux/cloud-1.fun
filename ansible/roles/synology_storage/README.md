# synology_storage

Storage of the cluster on the Synology NAS (RS812RP+, DSM 6.2.4), through
the DSM web API (the API of the web UI; undocumented for iSCSI, calls taken
from the UI code and tested on throwaway objects on 2026-11-04).

- **Audit** (default, read-only): every check runs, the verdict lists all the
  drifts at once. 16 checks, no drift on 2026-11-04.
- **Creation** (`storage_apply`, tag `storage-apply`): the missing iSCSI
  objects only: LUN (thin, Btrfs), target (one-way CHAP, several sessions per
  initiator for multipath), LUN mapping, masking (set again if it differs).
  Never deletes, resizes or renames; runs the audit afterwards. Idempotent
  (second run: no change).

| Object | Checks |
|---|---|
| LUN `lun-prox` | exists, on `/volume1`, 1000 GiB, recorded uuid (the LUN `synology-lvm` sits on), mapped |
| target `iqn.2026-10.lab.infra:prox` | exists, enabled, one-way CHAP with the user of the cluster, several sessions per initiator (multipath), maps the LUN |
| masking | exactly the IQNs of `host_vars/pveXX.yml` in rw, every other initiator denied |
| CHAP secret | equal to the vault of the cluster (`vault_pve_iscsi_chap_password`): compared, never displayed |
| share `iso` | on `/volume1`, NFS rule `10.1.20.0/24 rw`, root squash to admin; NFS service on |

The iSCSI values come from the Proxmox side (group `pve`, host_vars of the
nodes): one source for both ends of the link, a new IQN in the host_vars
shows up here as a drift until the NAS allows it.

## Use

```bash
make storage-check                  # audit, read-only
make storage-apply-check            # what would be created
make storage-apply CONFIRM=yes      # create the missing iSCSI objects, then audit
```

A recreated LUN gets a new uuid: the audit reports it, record it in
`storage_luns` (and the WWID read on a node in `pve_iscsi_lun_wwid`).

## Variables

`group_vars/storage/vars.yml`: DSM URL and account, `storage_luns`,
`storage_iscsi_targets`, `storage_nfs_shares`. DSM password in
`group_vars/storage/vault.yml` (`vault_dsm_admin_password`).

## Not covered yet

Creation of the NFS share: DSM wants its settings encrypted by the browser
(`Share.create` refuses them in clear); the share stays manual (runbook
8.2), its NFS rule is audited. Volume / disks, snapshots, DSM settings.

# synology_storage

Storage of the cluster on the Synology NAS (RS812RP+, DSM 6.2.4), **audited**
through the DSM web API (the API of the web UI; undocumented for iSCSI).
**Read-only**: nothing is created or changed. Every check runs, the verdict
lists all the drifts at once. Checked on 2026-11-04: 15 checks, no drift.

| Object | Checks |
|---|---|
| LUN `lun-prox` | exists, on `/volume1`, 1000 GiB, recorded uuid (the LUN `synology-lvm` sits on), mapped |
| target `iqn.2026-10.lab.infra:prox` | exists, enabled, one-way CHAP with the user of the cluster, maps the LUN |
| masking | exactly the IQNs of `host_vars/pveXX.yml` in rw, every other initiator denied |
| CHAP secret | equal to the vault of the cluster (`vault_pve_iscsi_chap_password`): compared, never displayed |
| share `iso` | on `/volume1`, NFS rule `10.1.20.0/24 rw`, root squash to admin; NFS service on |

The iSCSI values come from the Proxmox side (group `pve`, host_vars of the
nodes): one source for both ends of the link, a new IQN in the host_vars
shows up here as a drift until the NAS allows it.

## Use

```bash
make storage-check        # ansible-playbook 05-storage.yml
```

## Variables

`group_vars/storage/vars.yml`: DSM URL and account, `storage_luns`,
`storage_iscsi_targets`, `storage_nfs_shares`. DSM password in
`group_vars/storage/vault.yml` (`vault_dsm_admin_password`).

## Not covered yet

Creation (LUN, target, masking, share, NFS rule): to be written against
throwaway test objects first, the create calls of the API are undocumented.
Volume / disks, snapshots, DSM settings.

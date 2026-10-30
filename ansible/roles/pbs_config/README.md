# pbs_config

Proxmox Backup Server configuration (VM 2400 on the local-lvm of pve02):
repos, time, datastore, access for the cluster, prune / verify jobs and the
encrypted offsite copy. **Checked against the live VM on 2026-10-30**
(`--check --diff`, no real run yet): no change, vault secrets matching.

## Tasks

| File | What it does |
|---|---|
| `main.yml` | confirmation guard, then everything below in the order of a fresh install |
| `repos.yml` | enterprise repo disabled, `pbs-no-subscription` (deb822) |
| `system.yml` | own name in `/etc/hosts`, NTP on pfSense only (in `chrony.conf`, Debian pool removed) |
| `objects.yml` | generic: one kind of config object through the API (`proxmox-backup-debug api`), created when missing, differing options set on the existing ones; used for datastores, users, prune / verify jobs, remotes, sync jobs |
| `tokens.yml` | API tokens created when missing, then **`token.shadow` restored** from the vault (hashed secrets: the cluster keeps its token secret) |
| `acl.yml` | access rights added when missing |
| `keys.yml` | sync encryption keys imported when missing; recorded fingerprint and vault copy (checksum) checked |
| `remote_secrets.yml` | remote passwords (base64 in `remote.cfg`) compared with the vault, nothing displayed |

Real run refused unless `pbs_config_confirm=true`. Before creating a
datastore, its path must be a mounted disk (the data disk, `sdb`, ext4):
checked with `findmnt`, the disk itself is not prepared here.

## Variables

`group_vars/backup/vars.yml`: address, repos, NTP, and one list per object
kind (`pbs_datastores`, `pbs_users`, `pbs_tokens`, `pbs_acls`,
`pbs_prune_jobs`, `pbs_verify_jobs`, `pbs_encryption_keys`, `pbs_remotes`,
`pbs_sync_jobs`). Secrets in `group_vars/backup/vault.yml`:

| Variable | Content |
|---|---|
| `vault_pbs_token_shadow` | `/etc/proxmox-backup/token.shadow` verbatim (hashed secret of `pve@pbs!pve-cluster`) |
| `vault_pbs_remote_offsite_password` | secret of the `sync-push@pbs!rack` token on the offsite PBS (decoded) |
| `vault_pbs_offsite_key` | `encryption-keys/offsite-key.enc` verbatim: **same key** (fingerprint `dd:14:bc:…`) as the `pbs-offsite` storage of the cluster, without it no offsite backup can be restored |

## Rebuild

The PBS VM is excluded from the cluster backup job (it would back itself up
into its own datastore). After a loss of pve02, restore the guests straight
from the offsite PBS (`pbs-offsite` storage of the cluster, key in the
vault), reinstall the PBS VM, then run this role: the local datastore starts
empty and fills again with the next backups.

## Not covered yet

The offsite PBS itself (VPS, its datastore, prune and the `sync-push` /
`pve-restore` users), notifications, PBS host network (set by the
installer).

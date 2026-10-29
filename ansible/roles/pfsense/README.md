# pfsense

pfSense CE (FreeBSD) over SSH (Public Key Only, automation key on `admin`),
with the Python shipped by pfSense.

## Actions (`tasks_from`)

| File | What it does | Risk |
|---|---|---|
| `snapshot.yml` (default, `main.yml`) | copies `/cf/conf/config.xml` to `pfsense_snapshot_dir` (gitignored) | none |
| `backup.yml` | snapshot, then stores it vault-encrypted in `pfsense_config_vault` (versioned); rewritten only when the config changed | none on pfSense |
| `restore.yml` | pushes the versioned config, drops `/tmp/config.cache`, reboots | **overwrites the config, reboots the gateway and VPN** |

`restore.yml` refuses to run unless `pfsense_restore_confirm=true`.

Vault encryption uses a random salt: `backup.yml` compares the SHA-256 of the
fresh snapshot with the decrypted backup and re-encrypts only when they differ,
so an unchanged pfSense never shows a git change.

## Rebuild path

- **pfSense up, config broken**: `restore.yml` over SSH.
- **Fresh install** (no SSH, no key yet): pfSense loads a `config.xml` from a
  USB drive at boot when it finds `/config/config.xml` on it. Decrypt the
  backup (`ansible-vault decrypt --output /Volumes/<usb>/config/config.xml
  files/pfsense/config.xml.vault`), plug the drive, boot. The restored config
  brings back SSH and the authorized keys. Manual "point zero" step.

## Next steps

Config as code with `pfsensible.core`, object by object: aliases, rules, NAT,
then OpenVPN last. The backup stays as the safety net.

## Variables

Defaults in `defaults/main.yml`. From the inventory (`group_vars/firewall/`):
`ansible_user`, `ansible_ssh_private_key_file`, `ansible_python_interpreter`.

# pfsense

pfSense CE (FreeBSD) over SSH (Public Key Only, automation key on `admin`),
with the Python shipped by pfSense.

## Actions (`tasks_from`)

| File | What it does | Risk |
|---|---|---|
| `snapshot.yml` (default, `main.yml`) | copies `/cf/conf/config.xml` to `pfsense_snapshot_dir` (gitignored) and writes a `pfsense_resources.yml` proposal to diff against the host_vars | none |
| `backup.yml` | snapshot, then stores it vault-encrypted in `pfsense_config_vault` (versioned); rewritten only when the config changed | none on pfSense |
| `apply.yml` | pushes `host_vars/<firewall>/pfsense_resources.yml`: aliases, NAT port forwards and filter rules with `pfsense_aggregate` (rules in list order, nothing purged), then gateways, default gateway and static routes; real run refused unless `pfsense_apply_confirm=true` | changes pfSense |
| `restore.yml` | pushes the versioned config, drops `/tmp/config.cache`, reboots | **overwrites the config, reboots the gateway and VPN** |

`restore.yml` refuses to run unless `pfsense_restore_confirm=true`.

Vault encryption uses a random salt: `backup.yml` compares the SHA-256 of the
fresh snapshot with the decrypted backup (trailing newline normalised: pfSense
may write the file without one) and re-encrypts only when they differ, so an
unchanged pfSense never shows a git change.

## Configuration as code

`filter_plugins/pfsense_resources.py` (`pfsense_resources_from_config`) turns
`config.xml` into the `pfsense_aggregate` format: aliases and filter rules in
evaluation order (first match wins), NAT port forwards, gateways, default
gateway, static routes. Rules attached to a NAT port forward are not in
`rules`: `associated_rule: associated` makes them follow their port forward. pfsensible identifies a rule by name +
interface: rule descriptions must stay unique per interface.

## Rebuild path

- **pfSense up, config broken**: `restore.yml` over SSH.
- **Fresh install** (no SSH, no key yet): pfSense loads a `config.xml` from a
  USB drive at boot when it finds `/config/config.xml` on it. Decrypt the
  backup (`ansible-vault decrypt --output /Volumes/<usb>/config/config.xml
  files/pfsense/config.xml.vault`), plug the drive, boot. The restored config
  brings back SSH and the authorized keys. Manual "point zero" step.

## Next steps

System, DNS resolver and DHCP, then interfaces, then OpenVPN (CA, certs,
users, private keys in the vault) last. Outbound NAT is in automatic mode: no
rule to model.
The backup stays as the safety net.

## Variables

Defaults in `defaults/main.yml`. From the inventory (`group_vars/firewall/`):
`ansible_user`, `ansible_ssh_private_key_file`, `ansible_python_interpreter`.

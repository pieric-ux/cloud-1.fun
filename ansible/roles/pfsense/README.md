# pfsense

pfSense CE (FreeBSD) over SSH (Public Key Only, automation key on `admin`),
with the Python shipped by pfSense.

## Actions (`tasks_from`)

| File | What it does | Risk |
|---|---|---|
| `snapshot.yml` (default, `main.yml`) | copies `/cf/conf/config.xml` to `pfsense_snapshot_dir` (gitignored) and writes a `pfsense_resources.yml` proposal to diff against the host_vars | none |
| `backup.yml` | snapshot, then stores it vault-encrypted in `pfsense_config_vault` (versioned); rewritten only when the config changed | none on pfSense |
| `apply.yml` | pushes `host_vars/<firewall>/pfsense_resources.yml`: aliases, NAT port forwards and filter rules with `pfsense_aggregate` (rules in list order, nothing purged), then certificate authorities, certificates, users, OpenVPN servers, gateways, default gateway, static routes, system settings, DNS resolver and DHCP servers; starts with a drift guard, refreshes the backup after a real run; real run refused unless `pfsense_apply_confirm=true` | changes pfSense |
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

## Secrets

Keys, certificates, password hashes and the OpenVPN TLS key live in
`host_vars/<firewall>/vault.yml` (ansible-vault) as `vault_pfsense_secrets`;
`pfsense_resources.yml` only holds references. The snapshot writes both
proposals: `pfsense_resources.yml` (references) and `vault_secrets.yml`
(plain text, gitignored, 0600) to encrypt as the new `vault.yml`.

Tasks handling secrets run with `no_log` (`pfsense_hide_secrets`, default
true): `pfsense_openvpn_server` echoes the TLS key in its error messages.

Not managed, on purpose:
- the self-signed web UI certificate (no CA, generated and renewed by pfSense
  on install; `pfsense_cert` requires a CA);
- the user <-> certificate link (`pfsense_user` has no such option; VPN
  authentication is certificate based on the client side);
- SNMP, syslog, NTP server, cron, packages: covered by the encrypted backup.

The OpenVPN TLS key was stored with CRLF line endings (pasted from a browser):
the filter normalises it to LF, which pfsensible requires.

## Drift guard

`apply.yml` first compares the live configuration with the last versioned
backup, both through the filter (XML reformatting ignored). If they differ,
someone changed pfSense outside the code since the last backup (web UI, SSH)
and the apply stops: applying would overwrite or duplicate that change
(pfsensible identifies rules by name, so a renamed rule gets recreated).
Review the snapshot proposal, update the code or revert the change, run
`--tags pfsense-backup`, apply again. `-e pfsense_ignore_drift=true` skips the
guard when the change is known. After a real apply the backup is refreshed,
so it stays the reference.

## Rebuild path

- **pfSense up, config broken**: `restore.yml` over SSH.
- **Fresh install** (no SSH, no key yet): pfSense loads a `config.xml` from a
  USB drive at boot when it finds `/config/config.xml` on it. Decrypt the
  backup (`ansible-vault decrypt --output /Volumes/<usb>/config/config.xml
  files/pfsense/config.xml.vault`), plug the drive, boot. The restored config
  brings back SSH and the authorized keys. Manual "point zero" step.

## Next steps

Everything is modelled. Later: `purge_rules` / `purge_aliases` so the
web UI stops being a source of configuration (group decision). Outbound NAT is in automatic mode: no
rule to model.
The backup stays as the safety net.

## Variables

Defaults in `defaults/main.yml`. From the inventory (`group_vars/firewall/`):
`ansible_user`, `ansible_ssh_private_key_file`, `ansible_python_interpreter`.

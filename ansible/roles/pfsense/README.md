# pfsense

pfSense CE (FreeBSD) over SSH, with the Python shipped by pfSense.

## Actions (`tasks_from`)

| File | What it does | Risk |
|---|---|---|
| `snapshot.yml` (default, `main.yml`) | copies `/cf/conf/config.xml` to `pfsense_snapshot_dir` | none |

## Next steps

1. Rebuild path: restore `config.xml` (vault-encrypted) on a fresh install.
2. Config as code with `pfsensible.core`, object by object: aliases, rules,
   NAT, then OpenVPN last.

## Variables

Defaults in `defaults/main.yml`. From the inventory (`group_vars/firewall/`):
`ansible_user`, `ansible_password` (vault), `ansible_python_interpreter`.

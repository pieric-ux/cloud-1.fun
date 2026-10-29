# preflight

Read-only checks of the manual "point zero" (`docs/runbook-point-zero.md`),
run before a rebuild by `preflight.yml`. Changes nothing anywhere.

| File | Runbook step | Checks |
|---|---|---|
| `control.yml` (default, `main.yml`) | 1 | Python libs (`passlib`, `paramiko` < 4, pylibssh), collections, `key/ansible` (0600), every vault decrypts; warns on Docker / npx / vault password file mode |
| `switches.yml` | 2 | SSH port, Ansible login (`show version`) |
| `firewall.yml` | 3 | SSH port, login with the automation key |
| `storage.yml` | 4 | DSM port on the NAS addresses |
| `bmc.yml` | 5-7 | iLO HTTPS and credentials, RAID (`redfish_bootstrap` `raid_check`), stock ISO; warns when no prepared ISO |

A failing check stops that host and shows in the recap. Warnings (debug
messages) are for what only matters for an ISO build or an install.

## Variables

Defaults in `defaults/main.yml` (libraries, collections, NAS addresses until
the storage layer exists, timeouts). The rest comes from the inventory.

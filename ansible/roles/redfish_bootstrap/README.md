# redfish_bootstrap

Installs Proxmox VE on a bare-metal server through its BMC (Redfish API), from
an auto-install ISO built per host. Runs on the controller (`connection: local`):
the BMC has no shell nor Python, the modules are HTTPS clients.

## Actions (`tasks_from`)

| File | What it does | Risk |
|---|---|---|
| `probe.yml` (default, `main.yml`) | reads system, manager, virtual media, boot targets | none (GET only) |
| `media_test.yml` | mounts then ejects the stock ISO, checks no boot is armed | low: hot-plugged USB CD, no reboot |
| `build_iso.yml` | renders `answer.toml` + first-boot hook, validates, `prepare-iso` in Docker | none (local) |
| `install.yml` | mounts the prepared ISO, arms boot once, resets, waits for 8006 | **wipes the system disk** |

`install.yml` refuses to run unless `pve_install_confirm=true`; the playbook adds
`serial: 1` and `any_errors_fatal`.

## Vendor-specific calls

`tasks/<redfish_vendor>/` holds the BMC calls that differ between vendors:
`media_state`, `media_insert`, `media_eject`, `boot_once`. iLO 4 has no standard
`#VirtualMedia.InsertMedia`: it uses the `Oem.Hp` actions and
`Oem.Hp.BootOnNextServerReset`. An iLO 5 would add `tasks/ilo5/` with the
standard Redfish actions, nothing else changes.

## Variables

Role defaults in `defaults/main.yml` (Redfish paths, timeouts, ISO image name).
Expected from the inventory:

- `ilo_host`, `ilo_user`, `ilo_password`, `ilo_validate_certs`
- `iso_url` (stock ISO, media test), `pve_install_iso_url` (prepared ISO)
- `pve_iso_source`, `pve_iso_build_dir`
- `pve_install_*` and `pve_net_*` used by the templates (disk, NICs, network)

The playbook sets `module_defaults` for `ansible.builtin.uri` (BMC credentials).

## Templates

- `answer.toml.j2`: Proxmox 9.x answer (kebab-case keys). Disk matched by
  `ID_SERIAL`, root password hashed at render time (the ISO is served over HTTP).
- `first-boot.sh.j2`: writes the real network layout (LACP bonds, VLAN-aware
  bridge, mgmt VLAN) before networking starts; NICs matched by permanent MAC.

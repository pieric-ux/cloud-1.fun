# ios_switch

Cisco IOS switch configuration as code. The configuration lives in
`host_vars/<switch>/ios_resources.yml`, in the `cisco.ios` resource modules
format, and is pushed with one of two methods depending on the IOS.

## Actions (`tasks_from`)

| File | What it does | Risk |
|---|---|---|
| `snapshot.yml` (default, `main.yml`) | `show` commands only; writes `running-config.txt`, `resources.yml` (raw) and `ios_resources.yml` (proposal) to `ios_snapshot_dir` | none |
| `parse.yml` | offline parse of the saved running config (state parsed), for IOS without live parsers | none (never connects) |
| `apply.yml` | pushes `ios_resources`; real run refused unless `network_apply_confirm=true` | changes the switch |

Always preview with `--check --diff`: it must show no change while the code
matches the switch.

## Two apply modes (`ios_apply_mode`)

- `resources` (default, IOS 15.x): resource modules, `state: replaced`. Only the
  resources described are touched.
- `rendered` (old IOS such as 12.2): the live parsers need `show running-config
  | section`, missing there. Commands are rendered offline from the same YAML
  (`state: rendered`, connection forced to `127.0.0.1`), assembled by
  `templates/ios_candidate.j2` the way IOS displays them, then pushed with
  `ios_config`. Limit: `ios_config` adds what is missing, it does not remove
  what is extra.

Same data format for both: only the adapter changes.

## Filters (`filter_plugins/ios_resources.py`)

- `ios_resources_prune`: raw resources -> `ios_resources` (built-in VLANs
  dropped, default-only entries dropped, natural port order, IOS L3 defaults
  `redirects`/`unreachables` made explicit because `state: replaced` would
  otherwise send `no ip redirects`).
- `ios_vlans_from_config`: VLANs from a running config, where `ios_vlans`
  cannot parse offline.

To refresh the code after a change made on a switch: run the snapshot, then
diff `build/network/<switch>/ios_resources.yml` against the host_vars.

## Variables

Defaults in `defaults/main.yml`. From the inventory: connection settings
(`network_cli`, `paramiko`, credentials) and `ios_resources`.

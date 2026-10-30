# users

Accounts of every VM (layer 30): one personal admin account per person,
the automation account restricted to its key, legacy accounts removed.

## What it does

| File | Action |
|---|---|
| `admins.yml` | admin group, one account per person, SSH key only (password `*`: no usable password, but not locked, which sshd without PAM on Alpine refuses), passwordless sudo through the group |
| `automation.yml` | `authorized_keys` of the automation account reduced to `users_automation_keys` (`exclusive`) |
| `removed.yml` | legacy accounts removed (explicit list only, no `force`: a running session makes it fail instead of killing it) |

## Safeguards

- Refuses to run with an empty `users_admins`: removing the legacy accounts
  would leave nobody able to log in.
- Refuses an empty `users_automation_keys`: `exclusive` would remove every
  key, Ansible's included.

## Variables

Set in `inventory/group_vars/all/vars.yml`: `users_admins` (name + SSH keys),
`users_automation_keys`, `users_removed`. Defaults: `users_admin_group: admins`,
`users_automation_user: ansible`. Shell per OS in `vars/` (bash, ash on Alpine).

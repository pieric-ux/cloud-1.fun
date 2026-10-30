# ssh-hardening

sshd hardening of every VM (layer 30) through a drop-in, so the
distribution's `sshd_config` stays untouched.

## What it does

- `/etc/issue.net` legal banner.
- `/etc/ssh/sshd_config.d/20-ssh-hardening.conf`: no root login, no password
  nor keyboard-interactive authentication, keys only, `MaxAuthTries 3`,
  client alive 300 s × 2, banner.

sshd keeps the first value read for an option and reads the drop-ins before
its own settings: this file wins over the distribution defaults and over
`50-cloud-init.conf`.

## Safeguards against a lockout

- The drop-in is validated before being written (`sshd -t -f`).
- The handler validates the full configuration (`sshd -t`) before the
  reload: if it is invalid, the play stops and the running sshd keeps its
  previous configuration. Reload, not restart: open sessions survive.

## Variables

`ssh_hardening_*` in `defaults/main.yml` (yes/no values quoted: unquoted they
become YAML booleans). Service name per OS in `vars/`.

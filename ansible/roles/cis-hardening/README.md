# cis-hardening

CIS Level 1 Server settings for sshd (layer 30), the values an OpenSCAP
report expects.

## What it does

- `/etc/ssh/sshd_config` mode `0600`.
- `/etc/ssh/sshd_config.d/10-cis-hardening.conf`: `AllowGroups` (only the
  admin and automation groups may log in), ciphers / KEX / MACs restricted
  to the CIS list, no host-based authentication, `IgnoreRhosts`, login grace
  time, log level, `MaxSessions`, `MaxStartups`, no empty passwords, no user
  environment.

Read before `20-ssh-hardening.conf` (role `ssh-hardening`): on a conflict,
the CIS value wins. Validated before being written (`sshd -t -f`); reload
through the `ssh-hardening` handler.

## Variables

`cis_hardening_ssh_allow_groups` is set in `inventory/group_vars/all/vars.yml`
(`admins`, `ansible`); empty list: no `AllowGroups` line. Algorithm lists and
the other values in `defaults/main.yml`.

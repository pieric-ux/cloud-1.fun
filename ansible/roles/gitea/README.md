# gitea

Git server of the rack on `gitea01` (VM 2408): official Gitea binary
(version and checksum pinned), SQLite, systemd unit (hardened: writes only
in its home), first admin account created when missing.

- Web UI: `https://gitea.cloud-1.fun/` through the reverse proxy
  rproxy-int01 (TLS there, site in `ansible/files/rproxy/`); Gitea listens on
  3000 in clear, trusted proxy 10.1.240.33.
- Git over SSH: built-in Gitea SSH server on `gitea01.cloud-1.fun:2222`
  (the system sshd keeps port 22 for the admins).
- Sign-in required to view, registration closed.

Inside Gitea, through its API (`tasks/api.yml`, created when missing): the
admin SSH keys (the same as `users_admins`), the repositories of
`gitea_repos` (`cloud-1.fun`, private) and their **push mirror to GitHub**
(`https://github.com/pieric-ux/cloud-1.fun.git`, on every push and every
8 h, with a fine-grained token limited to that repository:
`vault_gitea_github_token`).

The repo itself: `origin` is
`ssh://git@gitea01.cloud-1.fun:2222/gitea-admin/cloud-1.fun.git`; GitHub is the
offsite copy, cloned from during a full rebuild (Gitea is a guest of the
rack).

Secrets in `group_vars/git/vault.yml` (`vault_gitea_secret_key`,
`vault_gitea_internal_token`, `vault_gitea_jwt_secret`,
`vault_gitea_admin_password`), generated on 2026-11-04. Backups: the whole VM
through PBS (job of 02:00).

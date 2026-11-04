# rproxy (nginx on rproxy-int01, LXC 2403)

Sites of the reverse proxy written from the repo, **applied by hand** on
2026-11-04 (`pct push` into `/etc/nginx/sites-available/`, symlink in
`sites-enabled/`, `nginx -t`, reload): the configuration of rproxy-int01 is
not managed by Ansible yet (the LXC containers have no `ansible` account).

| File | Purpose |
|---|---|
| `00-default` | default server on 80 / 443: names without a site are refused (444) instead of reaching the first site loaded (it was the Hak5 C2) |
| `gitea.cloud-1.fun` | Gitea (gitea01:3000), model of the Grafana site, 512 MiB bodies for git push |

The 13 other sites and the TLS certificate (Let's Encrypt wildcard
`cloud-1.fun`) are only on the container: to take over in a `rproxy` role.

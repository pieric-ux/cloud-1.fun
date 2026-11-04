# rproxy

Internal reverse proxy on rproxy-int01 (LXC 2403): nginx terminating TLS for
the web services of the rack (`<service>.cloud-1.fun` → rproxy-int01, see
`network/addressing.yml`), with the Let's Encrypt wildcard `*.cloud-1.fun`.
Taken over from the live container on 2026-11-04 (files kept as they were).

- `files/nginx.conf`, `files/websocket.conf`: main configuration (Debian
  default, TLS 1.2 / 1.3, `server_tokens off`) and the WebSocket map.
- `files/sites/`: one site per file, all enabled. `00-default` refuses the
  names without a site (444). Seven sites proxy to HTTPS backends with
  self-signed certificates (`proxy_ssl_verify off`).
- Certificate: certbot with the Debian plugin `dns-infomaniak` (DNS-01, the
  only way to get a wildcard); credentials in `group_vars/rproxy/vault.yml`
  (`vault_rproxy_infomaniak_ini`). Requested only when missing (rebuild),
  renewed by `certbot.timer` (reloads nginx).
- Every change goes through `nginx -t` before the reload.

Add a service: its site in `files/sites/`, its name in `services` of
`network/addressing.yml`. Access: the `ansible` account comes from the
`lxc_access` role.

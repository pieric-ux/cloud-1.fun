# pve-exporter

prometheus-pve-exporter on `prometheus01` (Python venv, systemd, local only:
127.0.0.1:9221), scraped by the `pve` job. Authenticates with the API token
`monitoring@pve!exporter` (role `PVEAuditor`, created by `pve_config`); its
secret is `vault_pve_exporter_token` (`group_vars/monitoring/vault.yml`). A
token recreated by a rebuild gets a new secret: update the vault. From
infra06.

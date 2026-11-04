# alertmanager

Prometheus Alertmanager on `prometheus01`: official release (checksum
verified), amtool-validated configuration, systemd unit, port 9093. From
infra06.

**Notifications are not wired yet**: every alert goes to the `null`
receiver (Discord / SMTP receivers to add in
`templates/alertmanager.yml.j2`, their secrets in a vault). Alerts are
visible in Alertmanager and Grafana, nobody is notified.

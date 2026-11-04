# grafana

Grafana on `grafana01` (official APT repository), with Prometheus as
provisioned data source (`http://prometheus01.cloud-1.fun:9090`). The admin
password is only set when `grafana_admin_password` is given (it never was in
production). From infra06.

Dashboards (`ansible/files/grafana-dashboards/`: overview, hosts, proxmox,
switches, custom rack dashboard) are imported by hand in the UI, not
provisioned (provisioning them now would duplicate the existing ones).

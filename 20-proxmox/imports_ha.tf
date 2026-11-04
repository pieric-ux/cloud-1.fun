# HA resources and rules (PVE 9: rules replace the HA groups), imported from
# the live cluster on 2026-11-04.
import {
  to = proxmox_haresource.dhcp_dns
  id = "vm:2401"
}
import {
  to = proxmox_haresource.vault_01
  id = "ct:2402"
}
import {
  to = proxmox_haresource.rproxy_int01
  id = "ct:2403"
}
import {
  to = proxmox_haresource.ansible
  id = "vm:2405"
}
import {
  to = proxmox_haresource.prometheus01
  id = "vm:2406"
}
import {
  to = proxmox_haresource.grafana01
  id = "vm:2407"
}
import {
  to = proxmox_haresource.c2_hak5
  id = "vm:2481"
}
import {
  to = proxmox_haresource.k3s_control
  id = "vm:1000"
}
import {
  to = proxmox_haresource.k3s_worker_1
  id = "vm:1001"
}
import {
  to = proxmox_haresource.k3s_worker_2
  id = "vm:1002"
}
import {
  to = proxmox_harule.home_pve01
  id = "home-pve01"
}
import {
  to = proxmox_harule.home_pve02
  id = "home-pve02"
}
import {
  to = proxmox_harule.prometheus_with_dns
  id = "prometheus-with-dns"
}

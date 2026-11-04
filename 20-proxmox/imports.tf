# Existing guests brought under Terraform: one import block per guest, code
# generated from the live VM ("terraform plan -generate-config-out"), then
# cleaned by hand until the plan shows no change. "terraform apply" then only
# records them in the state, nothing changes on Proxmox.
import {
  to = proxmox_virtual_environment_vm.grafana01
  id = "pve02/2407"
}

import {
  to = proxmox_virtual_environment_vm.k3s_control
  id = "pve01/1000"
}
import {
  to = proxmox_virtual_environment_vm.k3s_worker_1
  id = "pve01/1001"
}
import {
  to = proxmox_virtual_environment_vm.k3s_worker_2
  id = "pve01/1002"
}
import {
  to = proxmox_virtual_environment_vm.pbs
  id = "pve02/2400"
}
import {
  to = proxmox_virtual_environment_vm.dhcp_dns
  id = "pve01/2401"
}
import {
  to = proxmox_virtual_environment_container.vault_01
  id = "pve02/2402"
}
import {
  to = proxmox_virtual_environment_container.rproxy_int01
  id = "pve01/2403"
}
import {
  to = proxmox_virtual_environment_vm.ansible
  id = "pve01/2405"
}
import {
  to = proxmox_virtual_environment_vm.prometheus01
  id = "pve01/2406"
}
import {
  to = proxmox_virtual_environment_vm.c2_hak5
  id = "pve02/2481"
}
import {
  to = proxmox_virtual_environment_vm.sliver_c2
  id = "pve01/2483"
}
import {
  to = proxmox_virtual_environment_vm.captive_portal
  id = "pve01/2486"
}

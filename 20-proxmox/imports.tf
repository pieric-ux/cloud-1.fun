# Existing guests brought under Terraform: one import block per guest, code
# generated from the live VM ("terraform plan -generate-config-out"), then
# cleaned by hand until the plan shows no change. "terraform apply" then only
# records them in the state, nothing changes on Proxmox.
import {
  to = proxmox_virtual_environment_vm.grafana01
  id = "pve02/2407"
}

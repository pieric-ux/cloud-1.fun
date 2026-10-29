# Read-only for now: lists the guests of the cluster. Nothing here creates,
# changes or deletes anything; "terraform plan" only reads.
data "proxmox_virtual_environment_vms" "all" {}

output "vms" {
  description = "VMs of the cluster (vmid, name, node)"
  value = [
    for vm in data.proxmox_virtual_environment_vms.all.vms :
    { vmid = vm.vm_id, name = vm.name, node = vm.node_name }
  ]
}

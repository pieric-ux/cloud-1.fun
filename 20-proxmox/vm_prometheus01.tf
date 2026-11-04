# prometheus01: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_vm" "prometheus01" {
  boot_order  = ["scsi0", "net0"]
  description = "Debian 13, cloud-init, user ansible. Built by Packer (Benedict) on 2026-10-21T11:01:45Z"
  name        = "prometheus01"
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:B2:96:60"
    model       = "virtio"
    vlan_id     = 240
  }
  node_name     = "pve01"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  tags          = ["mgmt"]
  vm_id         = 2406
  agent {
    enabled = true
  }
  cpu {
    cores   = 2
    flags   = ["+md-clear", "+pcid", "+ssbd"]
    sockets = 1
    type    = "Haswell-noTSX-IBRS"
  }
  disk {
    datastore_id = "synology-lvm"
    file_format  = "raw"
    interface    = "scsi0"
    replicate    = false
    size         = 10
  }
  initialization {
    datastore_id = "synology-lvm"
    interface    = "ide1"
    ip_config {
      ipv4 {
        address = "${local.host_ip["prometheus01"]}/24"
        gateway = local.mgmt_gw
      }
    }
  }
  memory {
    dedicated = 4096
  }
  operating_system {
    type = "l26"
  }

  # HA guest: the HA and its rules (ha.tf) decide the node it runs on. A move
  # (failover, maintenance) must not make Terraform replace it.
  lifecycle {
    ignore_changes = [node_name]
  }
}

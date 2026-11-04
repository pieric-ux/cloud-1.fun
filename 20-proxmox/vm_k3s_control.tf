# k3s-control: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_vm" "k3s_control" {
  boot_order  = ["scsi0", "net0"]
  description = "Ubuntu 24.04, généré par Packer le 2026-10-26T13:42:22Z"
  name        = "k3s-control"
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:69:C9:EE"
    model       = "virtio"
    vlan_id     = 10
  }
  node_name     = "pve01"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  tags          = ["prod"]
  vm_id         = 1000
  agent {
    enabled = true
  }
  cpu {
    cores   = 2
    flags   = ["+pcid", "+md-clear", "+ssbd"]
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
    interface    = "ide0"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      username = "ansible"
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

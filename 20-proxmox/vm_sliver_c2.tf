# sliver-c2: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_vm" "sliver_c2" {
  boot_order  = ["scsi0", "net0"]
  description = "Debian 13, cloud-init, user ansible. Built by Packer (Benedict) on 2026-10-21T11:01:45Z"
  name        = "sliver-c2"
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:5D:DB:CA"
    model       = "virtio"
    vlan_id     = 240
  }
  node_name     = "pve01"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  tags          = ["mgmt", "pineapple"]
  vm_id         = 2483
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
    interface    = "ide1"
    dns {
      domain  = "cloud-1.fun"
      servers = ["10.1.240.31"]
    }
    ip_config {
      ipv4 {
        address = "10.1.240.83/24"
        gateway = "10.1.240.1"
      }
    }
  }
  memory {
    dedicated = 2048
  }
  operating_system {
    type = "l26"
  }
}

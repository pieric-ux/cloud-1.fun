# captive-portal: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_vm" "captive_portal" {
  boot_order  = ["scsi0", "net0"]
  description = "Debian 13, cloud-init, user ansible. Built by Packer (Benedict) on 2026-10-21T11:01:45Z"
  name        = "captive-portal"
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:9F:7F:91"
    model       = "virtio"
    vlan_id     = 240
  }
  node_name     = "pve01"
  on_boot       = false
  scsi_hardware = "virtio-scsi-single"
  tags          = ["template"]
  vm_id         = 2486
  agent {
    enabled = true
  }
  cpu {
    cores   = 1
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
      servers = ["10.1.240.31"]
    }
    ip_config {
      ipv4 {
        address = "${local.host_ip["captive-portal"]}/24"
        gateway = local.mgmt_gw
      }
    }
    user_account {
      username = "ansible"
    }
  }
  memory {
    dedicated = 256
  }
  operating_system {
    type = "l26"
  }
}

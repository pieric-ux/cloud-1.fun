# ansible: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_vm" "ansible" {
  boot_order  = ["scsi0", "net0"]
  description = "Ubuntu 24.04, généré par Packer le 2026-10-19T16:41:19Z"
  name        = "Ansible"
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:97:2C:D9"
    model       = "virtio"
    vlan_id     = 240
  }
  node_name     = "pve01"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  tags          = ["mgmt"]
  vm_id         = 2405
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
  memory {
    dedicated = 2048
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

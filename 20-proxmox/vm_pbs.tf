# pbs: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_vm" "pbs" {
  boot_order = ["scsi0"]
  name       = "pbs"
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:71:7D:52"
    model       = "virtio"
    vlan_id     = 240
  }
  node_name     = "pve02"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  tags          = ["mgmt"]
  vm_id         = 2400
  agent {
    enabled = true
  }
  cpu {
    cores   = 4
    flags   = ["+pcid", "+md-clear", "+ssbd"]
    sockets = 1
    type    = "Haswell-noTSX-IBRS"
  }
  disk {
    datastore_id = "local-lvm"
    discard      = "on"
    file_format  = "raw"
    interface    = "scsi0"
    iothread     = true
    replicate    = true
    size         = 16
  }
  disk {
    backup       = false
    datastore_id = "local-lvm"
    discard      = "on"
    file_format  = "raw"
    interface    = "scsi1"
    iothread     = true
    replicate    = true
    size         = 40
  }
  memory {
    dedicated = 4096
  }
  operating_system {
    type = "l26"
  }
}

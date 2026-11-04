# dhcp-dns: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_vm" "dhcp_dns" {
  boot_order = ["scsi0", "net0"]
  name       = "dhcp-dns"
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:A1:A6:FB"
    model       = "virtio"
    vlan_id     = 240
  }
  node_name     = "pve01"
  on_boot       = true
  scsi_hardware = "virtio-scsi-single"
  tags          = ["mgmt"]
  vm_id         = 2401
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
    discard      = "on"
    file_format  = "raw"
    interface    = "scsi0"
    iothread     = true
    replicate    = true
    size         = 12
  }
  memory {
    dedicated = 2048
  }
  operating_system {
    type = "l26"
  }
  startup {
    down_delay = -1
    order      = 1
    up_delay   = -1
  }
}

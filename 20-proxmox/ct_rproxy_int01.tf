# rproxy-int01: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_container" "rproxy_int01" {
  node_name     = "pve01"
  start_on_boot = true
  tags          = ["mgmt"]
  unprivileged  = true
  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }
  disk {
    datastore_id = "synology-lvm"
    replicate    = false
    size         = 4
  }
  features {
    nesting = true
  }
  initialization {
    hostname = "rproxy-int01"
    ip_config {
      ipv4 {
        address = "10.1.240.33/24"
        gateway = "10.1.240.1"
      }
    }
  }
  memory {
    dedicated = 512
    swap      = 512
  }
  network_interface {
    bridge      = "vmbr0"
    firewall    = true
    mac_address = "BC:24:11:C9:8F:44"
    name        = "eth0"
    vlan_id     = 240
  }
  operating_system {
    template_file_id = ""
    type             = "debian"
  }
}

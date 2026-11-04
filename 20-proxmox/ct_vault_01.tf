# vault-01: imported from the live guest on 2026-11-04.
resource "proxmox_virtual_environment_container" "vault_01" {
  environment_variables = {
    ENV_FILE     = "/data/.env"
    PATH         = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    SSL_CERT_DIR = "/etc/ssl/certs"
  }
  node_name     = "pve02"
  start_on_boot = true
  tags          = ["mgmt"]
  unprivileged  = true
  console {
    type = "console"
  }
  disk {
    datastore_id = "synology-lvm"
    replicate    = false
    size         = 2
  }
  features {
    nesting = true
  }
  initialization {
    entrypoint = "/start.sh"
    hostname   = "vault-01"
    ip_config {
      ipv4 {
        address = "10.1.240.32/24"
        gateway = "10.1.240.1"
      }
    }
  }
  memory {
    dedicated = 512
    swap      = 512
  }
  mount_point {
    acl           = false
    backup        = true
    mount_options = []
    path          = "/data"
    quota         = false
    read_only     = false
    replicate     = true
    shared        = false
    size          = "8G"
    volume        = "synology-lvm:vm-2402-disk-0"
  }
  network_interface {
    bridge       = "vmbr0"
    firewall     = true
    host_managed = true
    mac_address  = "BC:24:11:02:4D:81"
    name         = "eth0"
    vlan_id      = 240
  }
  operating_system {
    template_file_id = ""
    type             = "alpine"
  }

  # HA guest: the HA and its rules (ha.tf) decide the node it runs on. A move
  # (failover, maintenance) must not make Terraform replace it.
  lifecycle {
    ignore_changes = [node_name]
  }
}

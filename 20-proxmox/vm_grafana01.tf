# grafana01: Grafana (layer 30), MGMT VLAN, home node pve02 (HA rule
# home-pve02). Imported from the live VM on 2026-11-04, cloned from the
# Debian 13 template 8002 (Benedict).
resource "proxmox_virtual_environment_vm" "grafana01" {
  name        = "grafana01"
  node_name   = "pve02"
  vm_id       = 2407
  description = "Debian 13, cloud-init, user ansible. Built by Packer (Benedict) on 2026-10-21T11:01:45Z"
  tags        = ["mgmt"]
  on_boot     = true

  # Same model on every guest: live migration both ways (pve01 is Haswell).
  cpu {
    type    = "Haswell-noTSX-IBRS"
    flags   = ["+pcid", "+md-clear", "+ssbd"]
    sockets = 1
    cores   = 2
  }

  memory {
    dedicated = 2048
  }

  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0", "net0"]

  disk {
    datastore_id = "synology-lvm"
    interface    = "scsi0"
    file_format  = "raw"
    size         = 10
    # Provider default is true; storage replication is not used here.
    replicate = false
  }

  network_device {
    bridge      = "vmbr0"
    vlan_id     = 240
    model       = "virtio"
    mac_address = "BC:24:11:60:00:7B"
  }

  initialization {
    datastore_id = "synology-lvm"
    interface    = "ide1"
    ip_config {
      ipv4 {
        address = "${local.host_ip["grafana01"]}/24"
        gateway = local.mgmt_gw
      }
    }
  }

  agent {
    enabled = true
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

# gitea01: Git server of the rack (Gitea, layer 30), mirrored to GitHub.
# Created by Terraform, cloned from the Debian 13 template (8005, Packer).
resource "proxmox_virtual_environment_vm" "gitea01" {
  name        = "gitea01"
  node_name   = "pve01"
  vm_id       = 2408
  description = "Gitea (gitea.cloud-1.fun), mirrored to GitHub"
  tags        = ["mgmt"]
  on_boot     = true

  # Full clone of the template, which lives on pve01.
  clone {
    vm_id     = 8005
    node_name = "pve01"
    full      = true
  }

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

  # Template disk (10 GiB) grown to 20 GiB: repositories and LFS.
  disk {
    datastore_id = "synology-lvm"
    interface    = "scsi0"
    file_format  = "raw"
    size         = 20
    replicate    = false
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 240
    model   = "virtio"
  }

  initialization {
    datastore_id = "synology-lvm"
    interface    = "ide0"
    ip_config {
      ipv4 {
        address = "10.1.240.38/24"
        gateway = "10.1.240.1"
      }
    }
    dns {
      domain  = "cloud-1.fun"
      servers = ["10.1.240.31"]
    }
    user_account {
      username = "ansible"
      # Public part of the automation key (key/ansible.pub), as in the Packer
      # answer files.
      keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA/Cw4uZHVC34HkDoiCt/JiE8vdZCXLfGA6qOLsEl3e7 default@infra.fun"]
    }
  }

  agent {
    enabled = true
  }

  operating_system {
    type = "l26"
  }

  # HA guest: the HA and its rules (ha.tf) decide the node it runs on.
  lifecycle {
    ignore_changes = [node_name]
  }
}

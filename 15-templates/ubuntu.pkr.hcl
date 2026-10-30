# Ubuntu 24.04 template: autoinstall (http/ubuntu/user-data) served over HTTP.
source "proxmox-iso" "ubuntu2404" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure
  node                     = var.node

  vm_id           = var.vm_ids["ubuntu"]
  vm_name         = "ubuntu2404"
  os              = "l26"
  cpu_type        = var.cpu_type
  cores           = 2
  memory          = 2048
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true
  tags            = "template"

  disks {
    type         = "scsi"
    disk_size    = "10G"
    storage_pool = var.storage_pool
    format       = "raw"
  }

  network_adapters {
    model    = "virtio"
    bridge   = "vmbr0"
    vlan_tag = "240"
  }

  boot_iso {
    type         = "scsi"
    iso_file     = "${var.iso_storage}:iso/ubuntu-24.04.5-live-server-amd64.iso"
    unmount      = true
    iso_checksum = "sha256:97f3d7ffb032c3eb3b23d2c8be9cc76e60c2c1f2c0146ba5ba9fe01cafae0fd8"
  }

  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  http_directory    = "http/ubuntu"
  http_bind_address = var.http_ip
  http_port_min     = 8802
  http_port_max     = 8802

  boot_wait         = "10s"
  boot_key_interval = "50ms"
  boot_command = [
    "c<wait5s>",
    "linux /casper/vmlinuz --- autoinstall ds=\"nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/\"<enter><wait10s>",
    "initrd /casper/initrd<enter><wait30s>",
    "boot<enter>"
  ]

  ssh_username         = "ansible"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "30m"

  template_name        = "ubuntu2404-template"
  template_description = "Ubuntu 24.04, généré par Packer le ${timestamp()}"
}

build {
  name    = "ubuntu2404"
  sources = ["source.proxmox-iso.ubuntu2404"]

  # Generalize: new machine-id, network config and SSH host keys per clone.
  provisioner "shell" {
    execute_command = "sudo sh -eux '{{ .Path }}'"
    inline = [
      "cloud-init clean --machine-id --logs --configs network",
      "rm -f /etc/ssh/ssh_host_*_key*",
    ]
  }
}

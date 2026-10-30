# Debian 13 template: preseed (http/debian/preseed.cfg) served over HTTP.
source "proxmox-iso" "debian13" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure
  node                     = var.node

  vm_id           = var.vm_ids["debian"]
  vm_name         = "debian13"
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
    iso_file     = "${var.iso_storage}:iso/debian-13.7.0-amd64-netinst.iso"
    unmount      = true
    iso_checksum = "sha256:a7ef94ac2fb9a7fec454552abd629b7cc9d5155c886165a45649f5ce6167e355"
  }

  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  http_directory    = "http/debian"
  http_bind_address = var.http_ip
  http_port_min     = 8802
  http_port_max     = 8802

  boot_wait         = "10s"
  boot_key_interval = "50ms"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]

  ssh_username         = "ansible"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "30m"

  template_name        = "debian13-template"
  template_description = "Debian 13, généré par Packer le ${timestamp()}"
}

build {
  name    = "debian13"
  sources = ["source.proxmox-iso.debian13"]

  # Generalize; ifupdown only sources interfaces.d, written by cloud-init.
  provisioner "shell" {
    execute_command = "sudo sh -eux '{{ .Path }}'"
    inline = [
      "printf 'source /etc/network/interfaces.d/*\\n' > /etc/network/interfaces",
      "cloud-init clean --machine-id --logs --configs network",
      "rm -f /etc/ssh/ssh_host_*_key*",
    ]
  }
}

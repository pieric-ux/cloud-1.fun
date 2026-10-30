# Alpine 3.24 template: setup-alpine with http/alpine/answerfile, typed at the
# console. The installed system gets a static build address (no guest agent
# yet, so Packer could not learn a DHCP one) and is reached as root, the only
# account able to install sudo; root is locked again at the end and cloud-init
# creates the ansible user on each clone.
source "proxmox-iso" "alpine324" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  token                    = var.proxmox_token
  insecure_skip_tls_verify = var.proxmox_insecure
  node                     = var.node

  vm_id           = var.vm_ids["alpine"]
  vm_name         = "alpine3.24"
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
    iso_file     = "${var.iso_storage}:iso/alpine-virt-3.24.3-x86_64.iso"
    unmount      = true
    iso_checksum = "sha256:cdc1bc0efc64d8d611bf3733f54868172a545888dfd726f518bf279bcb0ff1af"
  }

  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  http_directory    = "http/alpine"
  http_bind_address = var.http_ip
  http_port_min     = 8803
  http_port_max     = 8803

  boot              = "order=scsi0;scsi1"
  boot_wait         = "45s"
  boot_key_interval = "50ms"
  boot_command = [
    "root<enter><wait5s>",
    "setup-interfaces -ar<enter><wait15s>",
    "wget -O /tmp/answers http://{{ .HTTPIP }}:{{ .HTTPPort }}/answerfile<enter><wait5s>",
    "export ERASE_DISKS=/dev/sda<enter>",
    "setup-alpine -e -f /tmp/answers && mount /dev/sda3 /mnt && printf 'auto lo\\niface lo inet loopback\\n\\nauto eth0\\niface eth0 inet static\\n    address ${var.alpine_build_ip}/24\\n    gateway 10.1.240.1\\n' > /mnt/etc/network/interfaces && umount /mnt && reboot<enter>"
  ]

  ssh_host             = var.alpine_build_ip
  ssh_username         = "root"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "30m"

  template_name        = "alpine-3.24-template"
  template_description = "Alpine 3.24, généré par Packer le ${timestamp()}"
}

build {
  name    = "alpine3.24"
  sources = ["source.proxmox-iso.alpine324"]

  provisioner "shell" {
    execute_command = "sh -eux '{{ .Path }}'"
    inline = [
      "apk update",
      "apk upgrade",
      "apk add sudo qemu-guest-agent cloud-init cloud-utils-growpart e2fsprogs-extra curl wget vim git htop python3 py3-pip",
      "echo 'ansible ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ansible",
      "chmod 440 /etc/sudoers.d/ansible",
      "visudo -c -f /etc/sudoers.d/ansible",
      "rc-update add qemu-guest-agent default",
      "setup-cloud-init",
      "grep -qx isofs /etc/modules || echo isofs >> /etc/modules",
      "printf 'system_info:\\n  default_user:\\n    name: ansible\\n    lock_passwd: false\\n    doas: [\"permit nopass ansible\"]\\n' > /etc/cloud/cloud.cfg.d/90-default-user.cfg",
      "rc-service qemu-guest-agent start",
      "rc-status --all | grep -E 'cloud-|qemu-guest' || true",
    ]
  }

  # Generalize: drop the static build address, the build key, lock root.
  provisioner "shell" {
    execute_command = "sh -eux '{{ .Path }}'"
    inline = [
      "mv /etc/network/interfaces.apk-new /etc/network/interfaces",
      "cloud-init clean --machine-id --logs --configs network",
      "rm -f /etc/ssh/ssh_host_*_key*",
      "rm -f /root/.ssh/authorized_keys",
      "usermod -p '*' ansible",
      "passwd -l root",
    ]
  }
}

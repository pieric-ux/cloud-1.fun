# Shared by the three templates. Values for this machine in
# templates.pkrvars.hcl (gitignored), see templates.pkrvars.example.hcl.

variable "proxmox_url" {
  description = "Proxmox VE API URL (any cluster node)"
  type        = string
  default     = "https://10.1.240.11:8006/api2/json"
}

variable "proxmox_username" {
  description = "API token ID (user@realm!token)"
  type        = string
  default     = "packer@pve!packer-token"
}

variable "proxmox_token" {
  description = "API token secret"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Accept the self-signed node certificate"
  type        = bool
  default     = true
}

variable "node" {
  description = "Node the templates are built on"
  type        = string
  default     = "pve01"
}

variable "vm_ids" {
  description = "VMID of each template (the build fails if it is taken)"
  type        = map(number)
  default = {
    alpine = 8003
    ubuntu = 8004
    debian = 8005
  }
}

# Same model on every guest so live migration works both ways: "host" exposes
# the CPU of the node the VM started on, and pve01 (Haswell) lacks
# instructions of pve02 (crash on migration). The flags of the team model
# (+pcid;+md-clear;+ssbd) are not settable here: added on the clones.
variable "cpu_type" {
  description = "QEMU CPU model of the templates (and of their clones)"
  type        = string
  default     = "Haswell-noTSX-IBRS"
}

variable "storage_pool" {
  description = "Storage of the disks and of the cloud-init drive"
  type        = string
  default     = "synology-lvm"
}

variable "iso_storage" {
  description = "Storage holding the install ISOs"
  type        = string
  default     = "synology-iso"
}

variable "http_ip" {
  description = "Address of this machine as seen from VLAN 240 (VPN: 10.100.0.x), serves the answer files"
  type        = string
}

variable "alpine_build_ip" {
  description = "Free static address on VLAN 240 for the Alpine build (no guest agent before the provisioner)"
  type        = string
}

variable "ssh_private_key_file" {
  description = "Automation key, its public part is in the answer files"
  type        = string
  default     = "../key/ansible"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  # The nodes use the self-signed certificate generated at install.
  insecure = var.proxmox_insecure
}

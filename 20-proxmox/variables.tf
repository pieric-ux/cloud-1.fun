variable "proxmox_endpoint" {
  description = "Proxmox VE API URL (any cluster node)"
  type        = string
  default     = "https://10.1.240.11:8006/"
}

variable "proxmox_api_token" {
  description = "API token \"user@realm!tokenid=secret\" (terraform.tfvars, gitignored)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Accept the self-signed node certificate"
  type        = bool
  default     = true
}

terraform {
  # import blocks + "plan -generate-config-out" (code generated from the
  # existing VMs) need Terraform >= 1.5.
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.119"
    }
  }

  # Local state, gitignored (*.tfstate): it holds secrets in clear. A remote
  # backend (MinIO / Synology) can come later, never in the repo.
}

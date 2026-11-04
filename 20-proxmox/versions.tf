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

  # State in HCP Terraform (encrypted, locked, versioned, reachable even with
  # the rack down). Execution mode Local: plans and applies run on this
  # machine, the only one that reaches the Proxmox API (HCP cannot). Login:
  # ~/.terraform.d/credentials.tfrc.json (user token, see README).
  cloud {
    organization = "cloud-1-fun"
    workspaces {
      name = "cloud-1-proxmox"
    }
  }
}

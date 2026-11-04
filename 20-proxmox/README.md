# 20-proxmox

Guests of the Proxmox cluster with Terraform (`bpg/proxmox`).

**Status: skeleton, read-only.** `inventory.tf` only lists the VMs. The guests
already exist: writing their resources by hand would make the first plan
replace them. They will be imported with generated code (`imports.tf.example`).

```bash
make vms-tfvars       # terraform.tfvars from the vault (token terraform@pve!iac)
make vms-init
make vms-plan         # reads only: outputs the VMs of the cluster
```

The token (user `terraform@pve`, role `TerraformProv`, ACL) is created by
`pve_config` (`access.yml`), which writes its secret to `terraform.tfvars`;
the secret alone is also kept in `group_vars/pve/vault.yml`
(`vault_pve_terraform_token`, the token ID is in the Makefile). After a rebuild the token is new: copy its
secret into the vault again.

State is local and gitignored (it holds secrets in clear); `terraform.tfvars`
is gitignored too, only the `.example` is versioned. `.terraform.lock.hcl` is
versioned (pins the provider build).

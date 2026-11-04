# 20-proxmox

Guests of the Proxmox cluster with Terraform (`bpg/proxmox`).

**Status: the 13 running guests are imported** (2026-11-04), the plan shows
no change. One file per guest (`vm_<name>.tf`, `ct_<name>.tf` for the LXC
containers); templates (Packer, layer 15) and stopped test VMs are left out.
`inventory.tf` lists every VM of the cluster (output only).

Import method, for a guest added by hand:

1. `import` block in `imports.tf` (`id = "<node>/<vmid>"`);
2. `terraform plan -generate-config-out=generated.tf`: code written from the
   live guest;
3. keep only what describes the guest (nulls, provider defaults and computed
   attributes removed; the provider defaults that differ from Proxmox written
   explicitly, e.g. `replicate`), until the plan shows only the import;
4. `terraform plan -out=tfplan` then `terraform apply tfplan`: recorded in the
   state, nothing changes on Proxmox.

Every VM sets its CPU explicitly (`Haswell-noTSX-IBRS` + flags): on a clone,
the provider would otherwise apply its own default (`qemu64`) instead of the
template's model. Containers: the import leaves the provider-side
`timeout_start` empty in the state, one `apply` on them fills it (no change
on Proxmox).

```bash
make vms-tfvars       # terraform.tfvars from the vault (token terraform@pve!iac)
make vms-init
make vms-plan         # must show no change
```

The token (user `terraform@pve`, role `TerraformProv`, ACL) is created by
`pve_config` (`access.yml`), which writes its secret to `terraform.tfvars`;
the secret alone is also kept in `group_vars/pve/vault.yml`
(`vault_pve_terraform_token`, the token ID is in the Makefile). After a
rebuild the token is new: copy its secret into the vault again.

State is local and gitignored (it holds secrets in clear); `terraform.tfvars`
is gitignored too, only the `.example` is versioned. `.terraform.lock.hcl` is
versioned (pins the provider build).

# 20-proxmox

Guests of the Proxmox cluster with Terraform (`bpg/proxmox`).

**Status: the 13 running guests are imported** (2026-11-04), the plan shows
no change. One file per guest (`vm_<name>.tf`, `ct_<name>.tf` for the LXC
containers); templates (Packer, layer 15) and stopped test VMs are left out.
`inventory.tf` lists every VM of the cluster (output only). `ha.tf`: the 10
HA resources and the 4 HA rules (PVE 9 rules, no HA groups; `proxmox_haresource` / `proxmox_harule`, the new names of the provider), each HA
resource referencing its guest and each rule its HA resources, so a rebuild
creates them in order (`imports_ha.tf` for their import).

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

**State in HCP Terraform** (organization `cloud-1-fun`, workspace
`cloud-1-proxmox`, execution mode **Local**): encrypted, locked during a run,
versioned, and reachable with the rack down. Plans and applies still run on
this machine: the provider calls the Proxmox API (`https://10.1.240.11:8006`)
from where Terraform runs, which HCP servers cannot reach. Login once, with a
**user** token (Account settings > Tokens; an organization token cannot run
plans), stored in `~/.terraform.d/credentials.tfrc.json`, mounted into the
Terraform container by the Makefile:

```bash
docker run --rm -it -v $HOME/.terraform.d:/root/.terraform.d hashicorp/terraform:1.9.8 login
```

From the MGMT VLAN (no VPN), Docker (OrbStack) needs the macOS *Local
Network* permission to reach the nodes. `terraform.tfvars` is gitignored,
only the `.example` is versioned. `.terraform.lock.hcl` is versioned (pins
the provider build).

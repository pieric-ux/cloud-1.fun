# 20-proxmox

Guests of the Proxmox cluster with Terraform (`bpg/proxmox`).

**Status: skeleton, read-only.** `inventory.tf` only lists the VMs. The guests
already exist: writing their resources by hand would make the first plan
replace them. They will be imported with generated code (`imports.tf.example`).

```bash
cp terraform.tfvars.example terraform.tfvars   # fill the API token
terraform init
terraform plan        # reads only: outputs the VMs of the cluster
```

State is local and gitignored (it holds secrets in clear); `terraform.tfvars`
is gitignored too, only the `.example` is versioned. `.terraform.lock.hcl` is
versioned (pins the provider build).

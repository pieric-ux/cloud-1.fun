# 15-templates

VM templates of the cluster with Packer (`proxmox-iso`): Alpine 3.24,
Ubuntu 24.04 and Debian 13, installed unattended from the ISOs on
`synology-iso`, then generalized (new machine-id, SSH host keys and network
config on each clone, through cloud-init). Terraform (layer 20) clones them.

Taken from `42-piscine-infra/infra04/packer/pieric`, with:

- **CPU model `Haswell-noTSX-IBRS`** instead of `host` (variable `cpu_type`):
  clones inherit it, and a VM started with `host` on pve02 crashes when it
  migrates to pve01 (older CPU). The team flags (`+pcid;+md-clear;+ssbd`)
  are not settable through the Packer plugin: added on the clones.
- Debian: one root partition, last on the disk, and a swap file instead of
  the swap partition of the `atomic` recipe, which sat after the root and
  kept cloud-init from growing it on a clone with a bigger disk (seen on
  gitea01, fixed by hand there). Template 8005 rebuilt on 2026-11-04: a
  clone with a 20 GiB disk gets a 20 GiB root by itself.
- one directory, shared variables (`variables.pkr.hcl`), API token and
  addresses in `templates.pkrvars.hcl` (gitignored).

| Template | VMID | Install | Build user |
|---|---|---|---|
| `alpine-3.24-template` | 8003 | `setup-alpine` + `http/alpine/answerfile`, static build address | `root` (only account able to install sudo), locked at the end |
| `ubuntu2404-template` | 8004 | autoinstall, `http/ubuntu/user-data` | `ansible` |
| `debian13-template` | 8005 | preseed, `http/debian/preseed.cfg` | `ansible` |

On every clone: user `ansible` (cloud-init), SSH key `key/ansible` only
(password locked), passwordless sudo, qemu-guest-agent.

## Use

```bash
make templates-vars                     # templates.pkrvars.hcl from the vault (HTTP_IP= to force)
make templates-check                    # init + fmt + validate, no API call
make templates CONFIRM=yes              # build the three, one at a time
make templates CONFIRM=yes ONLY='ubuntu2404.*'           # only one
```

Prerequisites:

- token `packer@pve!pieric` (privilege separation off, rights of
  `PackerRole`): its secret is `vault_pve_packer_token` in the pve vault;
- `http_ip` reachable from VLAN 240 on TCP 8802 / 8803 (the VM downloads its
  answer file from this machine: over the VPN, the tunnel address);
- `alpine_build_ip`: a free address of VLAN 240;
- **the VMID free**: the build fails on an existing VM; remove the old
  template first (no VM is a linked clone of them, all full clones).
- after the build, add the CPU flags the plugin cannot set:
  `qm set <vmid> --cpu 'Haswell-noTSX-IBRS,flags=+pcid;+md-clear;+ssbd'`.

Builds run one at a time (`-parallel-builds=1`): Ubuntu and Debian serve
their answer file on the same port.

## Not covered yet

Template refresh schedule (packages are updated at build time only), the
team templates 8001 / 8002 (kept as is).

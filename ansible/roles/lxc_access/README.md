# lxc_access

Automation account `ansible` (SSH key `key/ansible.pub`, passwordless sudo)
in the LXC containers, like the `users` role does on the VMs. A container
has only `root` with the team keys until then, so the account is made with
`pct exec` on the Proxmox node hosting it (found through the cluster API:
the HA may have moved it). Idempotent: installs sudo, the account, its key
and its sudoers file only when they differ.

Inventory: `lxc_vmid` per container (`inventory/lxc.yml`). Not run in
`--check` (pct exec has no dry run).

# lxc_access

Automation account `ansible` (SSH key `key/ansible.pub`, passwordless sudo)
in the LXC containers, like the `users` role does on the VMs. A container
has only `root` with the team keys until then, so the account is made with
`pct exec` on the Proxmox node hosting it (found through the cluster API:
the HA may have moved it). Idempotent: installs sudo, the account, its key
and its sudoers file only when they differ. The keys of `root` are those of
`users_admins` (the personal admin keys), replaced when they differ.

Inventory: `lxc_vmid` per container (`inventory/lxc.yml`). Not run in
`--check` (pct exec has no dry run).

Applied to rproxy-int01 only: vault-01 is an application container
(Vaultwarden OCI image, Alpine without SSH nor Python) that Ansible cannot
manage; it comes back from its backup (`/data`), see the runbook.

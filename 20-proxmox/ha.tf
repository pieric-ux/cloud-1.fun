# High availability (PVE 9: rules replace the HA groups). A guest restarts on
# the other node when its node fails; the rules say where it runs normally.
# Not HA: pbs (disk local to pve02), sliver-c2, captive-portal.

resource "proxmox_haresource" "dhcp_dns" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.dhcp_dns.id}"
  state        = "started"
  comment      = "DHCP-DNS"
  max_restart  = 5
  max_relocate = 3
}

resource "proxmox_haresource" "vault_01" {
  resource_id  = "ct:${proxmox_virtual_environment_container.vault_01.id}"
  state        = "started"
  comment      = "vault"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "rproxy_int01" {
  resource_id  = "ct:${proxmox_virtual_environment_container.rproxy_int01.id}"
  state        = "started"
  comment      = "rproxy-int01"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "ansible" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.ansible.id}"
  state        = "started"
  comment      = "Ansible"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "prometheus01" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.prometheus01.id}"
  state        = "started"
  comment      = "prometheus01"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "grafana01" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.grafana01.id}"
  state        = "started"
  comment      = "grafana01"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "c2_hak5" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.c2_hak5.id}"
  state        = "started"
  comment      = "C2-Hak5"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "k3s_control" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.k3s_control.id}"
  state        = "started"
  comment      = "K3S"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "k3s_worker_1" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.k3s_worker_1.id}"
  state        = "started"
  comment      = "K3S"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_haresource" "k3s_worker_2" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.k3s_worker_2.id}"
  state        = "started"
  comment      = "K3S"
  max_restart  = 3
  max_relocate = 2
}

# Normal placement on pve01 (not strict: they move to pve02 if pve01 fails).
resource "proxmox_haresource" "gitea01" {
  resource_id  = "vm:${proxmox_virtual_environment_vm.gitea01.id}"
  state        = "started"
  comment      = "Gitea"
  max_restart  = 3
  max_relocate = 2
}

resource "proxmox_harule" "home_pve01" {
  rule = "home-pve01"
  type = "node-affinity"
  nodes = {
    pve01 = null
  }
  resources = [
    proxmox_haresource.rproxy_int01.resource_id,
    proxmox_haresource.k3s_control.resource_id,
    proxmox_haresource.k3s_worker_1.resource_id,
    proxmox_haresource.dhcp_dns.resource_id,
    proxmox_haresource.prometheus01.resource_id,
  ]
}

# Normal placement on pve02.
resource "proxmox_harule" "home_pve02" {
  rule = "home-pve02"
  type = "node-affinity"
  nodes = {
    pve02 = null
  }
  resources = [
    proxmox_haresource.vault_01.resource_id,
    proxmox_haresource.grafana01.resource_id,
    proxmox_haresource.k3s_worker_2.resource_id,
    proxmox_haresource.gitea01.resource_id,
  ]
}

# Prometheus resolves its targets through dhcp-dns: kept on the same node.
resource "proxmox_harule" "prometheus_with_dns" {
  rule     = "prometheus-with-dns"
  type     = "resource-affinity"
  affinity = "positive"
  resources = [
    proxmox_haresource.dhcp_dns.resource_id,
    proxmox_haresource.prometheus01.resource_id,
  ]
}


# The two k3s workers never on the same node: the k3s cluster keeps a worker
# when a node fails (home-pve01 / home-pve02 place them apart normally).
resource "proxmox_harule" "k3s_workers_apart" {
  rule     = "k3s-workers-apart"
  type     = "resource-affinity"
  affinity = "negative"
  resources = [
    proxmox_haresource.k3s_worker_1.resource_id,
    proxmox_haresource.k3s_worker_2.resource_id,
  ]
}

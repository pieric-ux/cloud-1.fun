# Addressing of the rack: network/addressing.yml is the single source of the
# guest addresses here and of DHCP / DNS (role dnsmasq).
locals {
  addressing = yamldecode(file("${path.module}/../network/addressing.yml"))
  host_ip    = { for host in local.addressing.hosts : host.name => host.ip }
  mgmt_gw    = local.addressing.networks.mgmt.gateway
}

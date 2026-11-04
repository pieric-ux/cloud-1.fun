# Copy to templates.pkrvars.hcl (gitignored) and fill in.
# Token of packer@pve (Datacenter > Permissions > API Tokens).
proxmox_username = "packer@pve!pieric"
proxmox_token    = "00000000-0000-0000-0000-000000000000"
# This machine seen from VLAN 240 (over the VPN: the tunnel address).
http_ip         = "10.100.0.3"
alpine_build_ip = "10.1.240.250"

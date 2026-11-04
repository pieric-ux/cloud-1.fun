# Existant du repo piscine — à reprendre dans les couches suivantes

Relevé du 2026-10-30 dans `~/Documents/42-piscine-infra` (lecture seule) : ce
qui existe déjà, où, et ce que chaque couche à venir devra en reprendre. Les
valeurs viennent de la doc des modules : **à vérifier sur le rack** avant de
s'en servir (relevé réel des Proxmox à faire).

## Cluster Proxmox (→ rôle `pve_config`, couche 10)

Source : `infra03/docs/module03/cluster_setup.md`, `proxmox_setup.md`.

| Élément | Valeur |
|---|---|
| Cluster | `INFRA-CLUSTER`, corosync link0 sur MGMT (`10.1.240.11` / `.12`), knet, secauth |
| Quorum | QDevice `qdevice03` (Raspberry Pi 4B, Debian 13, `10.1.240.13`) → 3 votes |
| Migration | `bond1` direct 10 GbE `10.1.230.0/30`, `migration: network=10.1.230.1/30,type=secure` |
| datacenter.cfg | `ha: shutdown_policy=migrate`, `crs: ha=static` |
| Dépôts | enterprise + ceph désactivés, `pve-no-subscription` (deb822), dépôt **HPE MCP** (`ssacli`) |
| NTP | chrony, pfSense `10.1.255.2` seul (`sources.d/pfsense.sources`) |

**HA** (relevé du 2026-11-04, décrit dans `20-proxmox/ha.tf`) : 10
ressources (`max_restart 3`, `max_relocate 2`, dhcp-dns `5` / `3`) :
`vm:2401` dhcp-dns, `ct:2402` vault-01, `ct:2403` rproxy-int01, `vm:2405`
Ansible, `vm:2406` prometheus01, `vm:2407` grafana01, `vm:2481` c2-hak5,
`vm:1000-1002` k3s. Règles : `node-affinity home-pve01` (2403, 1000, 1001,
2401, 2406), `home-pve02` (2402, 2407, 1002), `resource-affinity` positive
`prometheus-with-dns` (2401 + 2406), négative `k3s-workers-apart` (1001 et
1002 jamais sur le même nœud, depuis le 2026-11-04 ; avant : les trois k3s
forcés ensemble). Hors HA : pbs (disque local), sliver-c2, captive-portal.

**Modèle CPU** des VMs migrables : `Haswell-noTSX-IBRS,flags=+pcid;+md-clear;+ssbd`
(nœud le plus ancien ; `host` fait planter la migration pve02 → pve01).
Templates 8001 / 8002 idem.

## Stockage (→ `pve_config` + `05-storage`)

Source : `iscsi_setup.md`, `proxmox_integration.md`, `nas_network.md`.

| Élément | Valeur |
|---|---|
| NAS | Synology RS812RP+, DSM 6.2.4 (dernière version), LAN1 `10.1.20.21`, LAN2 `10.1.20.22` |
| Volume | 1 disque WD 4 To, Btrfs, `/volume1` — **aucune redondance** |
| LUN | `lun-prox`, 1000 Gio thin |
| Cible | `iqn.2026-10.lab.infra:prox`, CHAP unidirectionnel (user `pveiscsi`), portails `.21` et `.22` |
| Masking | IQN pve01 `iqn.1993-08.org.debian:01:4f2abc6bf3c7`, pve02 `…:71b758bf9777`, défaut **aucun accès** |
| Proxmox | `synology-iscsi` (content none), `synology-lvm` (VG `vg-synology`, shared), `synology-iso` (NFS `/volume1/iso`) |
| Multipath | alias `mpath-synology`, WWID `360014051fae838bdedf5d4c82d85dadd`, `find_multipaths strict` |

## Guests (→ couche 20, Terraform)

Convention VMID : 1000-1999 PROD, 2400-2499 MGMT, 3000-3555 DMZ, 8000-8999
templates, 9000-9999 tests.

| VMID | Nom | Type | Stockage | Nœud (home) | HA |
|---|---|---|---|---|---|
| 2400 | `pbs` | VM | **`local-lvm` pve02** (survit à une panne du NAS) | pve02 | non |
| 2401 | `dhcp-dns` | VM | `synology-lvm` | pve01 | oui |
| 2402 | `vault-01` | LXC | `synology-lvm` | pve02 | oui |
| 2403 | `rproxy-int01` | LXC | `synology-lvm` | pve01 | oui |
| 2405 | `ansible` | VM | ? | ? | ? |
| 2406 | `prometheus01` | VM | `synology-lvm` | pve01 | oui |
| 2407 | `grafana01` | VM | `synology-lvm` | pve02 | oui |
| 1001 | `nettest` | VM | ? | ? | ? |
| 8001 | `ubuntu2404-template` | template | ? | ? | — |
| 8002 | Debian 13 template | template | ? | ? | — |

Exemple complet (`dhcp-dns`, `first_vm.md`) : Ubuntu 24.04.5 minimisé, 1
socket / 1 cœur, 2048 Mio, `scsi0` 12 Gio `synology-lvm` (`discard=on`,
`iothread=1`, `virtio-scsi-single`), `net0` virtio `vmbr0` tag 240, MAC
`BC:24:11:A1:A6:FB`, `agent: 1`, tag `mgmt`. PBS : 4 vCPU, 4 Gio, système 16
Gio + datastore 40 Gio (`backup=0`), `10.1.240.30`.

→ Importés le 2026-11-04 avec génération de code (`20-proxmox/imports.tf`),
ces valeurs servent à vérifier le code généré.

## Templates Packer (→ couche 20)

Source : `infra04/packer/` (un dossier par personne).
`pieric/` : `ubuntu2404.pkr.hcl`, `debian13.pkr.hcl`, `alpine3.24.pkr.hcl`.
Ubuntu : plugin `hashicorp/proxmox`, `proxmox-iso`, node pve01, VMID 8004,
2 cœurs / 2048 Mio, disque 10 Go `synology-lvm`, `vmbr0` tag 240, ISO depuis
`synology-iso`, cloud-init, user `ansible`, template `ubuntu2404-template`.
⚠️ `cpu_type = "host"` dans ce fichier, alors que les templates d'équipe
utilisent le modèle Haswell (migration) : à aligner.

## Supervision (→ couche 30) : reprise le 2026-11-04

Rôles d'infra06 dans `ansible/roles/` (`node-exporter`, `prometheus`,
`alertmanager`, `pve-exporter`, `snmp-exporter`, `snmptrapd`, `grafana`),
plays dans `30-config.yml`, tableaux de bord dans
`ansible/files/grafana-dashboards/` (import manuel). La config en service
avait été retouchée à la main (jobs et modules SNMP du STP, auth
`rack_v2_vlan240` = communauté + `@240`) : les rôles ont été alignés dessus,
`--check` sans écart. Secrets dans `group_vars/monitoring/vault.yml`.
Alertmanager n'envoie encore aucune notification (récepteur `null`).

## Kubernetes (→ couche 30) : reprise le 2026-11-04

Rôles `k3s-control` / `k3s-worker` d'infra05 (k3s `v1.31.4+k3s1`, Calico à
la place de Flannel pour les NetworkPolicies), plays dans `30-config.yml`,
jeton du cluster dans `group_vars/k3s/vault.yml`. Script d'installation figé
sur la release (au lieu de `get.k3s.io`). Manifests (`infra05/k8s/module05/`:
nginx + ingress, network policies, Postgres) pas encore repris.

## Sauvegardes hors site (→ restauration après rebuild)

Source : `infra/guide/pbs-offsite-tuto.md`.
PBS sur un serveur distant `pbs-offsite` (VPS, 4 vCPU, 7,8 Gio, datastore
`offsite1` sur un disque de 500 Go), alimenté par un **sync job en push
chiffré** depuis le PBS du rack ; port 8007 ouvert au rack seulement.
⚠️ **Pour restaurer après un crash total, il faut la clé de chiffrement du
sync job** (et l'accès au serveur distant) : dans le gestionnaire de mots de
passe de l'équipe. À référencer dans le runbook (étape « restauration »).

## Divers

- `infra02/docs/module02/` : configs des switchs avant/après, ACL L3, config
  pfSense, captures.
- `infra/guide/` : tutos VPN, Wi-Fi 2 SSID (AP Aironet), PBS, Packer.
- `docs/software/` : notes par logiciel (pfSense, IOS, k3s, PBS, DSM…).

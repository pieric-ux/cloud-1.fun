# cloud-1-iac

Infrastructure as Code du rack **cloud-1** (42 Lausanne — Piscine Infrastructure).

Objectif : **remonter toute l'infra à partir de ce repo**, du métal jusqu'aux
VMs, de façon reproductible et versionnée. Si tout crashe, on reconfigure tout
par l'automatisation, puis on restaure les backups (pve02 + copie remote).

> Contexte détaillé, décisions et état d'avancement : [`docs/context.md`](docs/context.md).

## Couches

| Couche | Rôle | Outil |
|---|---|---|
| **00 — network** | Switchs Cisco L2/L3 + pfSense | Ansible |
| **10 — bootstrap** | Installer Proxmox sur pve01/pve02 via l'iLO | Ansible (Redfish) + ISO Proxmox auto-install |
| **20 — proxmox** | VMs (templates Packer, cloud-init, VLAN, `synology-lvm`) | Terraform `bpg/proxmox` |
| **30 — config** | Users, durcissement SSH/CIS, services | Ansible |

Les numéros suivent l'ordre d'exécution d'un rebuild complet (porté par le
`Makefile`), avec des trous pour insérer une couche (le Synology deviendra
`05-storage`) :

```
point zéro manuel → réseau (00) → Synology → bare metal (10) → VMs (20) → config (30) → restauration des backups
```

## Structure

```
cloud-1-iac/
├── ansible/              # projet Ansible partagé par les couches 00, 10 et 30
│   ├── site.yml          # point d'entrée : importe 00 → 10 → 30
│   ├── 00-network.yml    # appelle les rôles ios_switch et pfsense
│   ├── 10-bootstrap.yml  # appelle le rôle redfish_bootstrap
│   ├── 30-config.yml
│   ├── preflight.yml     # vérifie le point zéro avant un rebuild
│   ├── inventory/        # zones/ (où) + baremetal/vms/lxc/network (quoi), group_vars, host_vars
│   └── roles/
│       ├── ios_switch/         # couche 00 : switchs Cisco, config as code
│       ├── pfsense/            # couche 00 : pfSense, config as code + backup chiffré
│       ├── redfish_bootstrap/  # couche 10 : BMC (iLO), RAID, ISO auto-install, réinstallation
│       ├── preflight/          # vérifications du point zéro (lecture seule)
│       └── common, users, ssh-hardening, cis-hardening   # couche 30
├── 10-bootstrap/         # hors Ansible : Dockerfile, ISO de base (gitignoré), build/ (gitignoré)
├── 20-proxmox/           # Terraform
├── build/                # gitignoré : snapshots réseau
├── key/                  # gitignoré : clé SSH automation
├── docs/
└── Makefile
```

Les playbooks ne contiennent aucune logique : un appel de rôle par action
(`import_role` + `tasks_from`), choisi par tag. Chaque rôle a un README et un
`tasks/main.yml` qui ne lance que son action sans danger (lecture seule).

## Prérequis (machine de contrôle)

- **Ansible** via pipx, avec passlib (filtre `password_hash` depuis Python
  3.13), et les bibliothèques SSH des switchs. Les IOS 12.2/15.2 n'offrent que
  du kex SHA-1 : paramiko < 4 obligatoire.
  ```bash
  pipx install --include-deps ansible
  pipx inject ansible passlib ansible-pylibssh 'paramiko<4'
  ```
- **Collections Ansible** :
  ```bash
  ansible-galaxy collection install -r ansible/requirements.yml
  ```
- **Mot de passe du vault** dans `~/.ansible/.vault_pass_cloud1` (droits `600`,
  hors repo), référencé par `vault_password_file` dans `ansible/ansible.cfg`.
  Le mot de passe est rangé dans Bitwarden.
- **Clé SSH automation** dans `key/` (gitignoré) : `key/ansible`, droits `600`.
- **Node.js / npx** : sert l'ISO aux iLO (`npx http-server`, requêtes HTTP Range
  obligatoires — `python3 -m http.server` ne convient pas).
- **Docker** : conteneur Debian pour `proxmox-auto-install-assistant`
  (paquet Debian, ne tourne pas sur macOS).
- Le laptop doit être joignable par les iLO (réseau mgmt `10.1.240.0/24`).

## Point zéro (étapes manuelles)

Ce qui ne peut pas être automatisé, car aucune API n'existe encore à ce stade :

1. Câblage, et IP de management des switchs (console série).
2. Installation de DSM et premier compte admin sur le Synology.
3. Compte iLO sur chaque serveur (automatisable plus tard via Redfish).

Le runbook détaillé (quoi, pourquoi, comment vérifier, dans l'ordre) est dans
[`docs/runbook-point-zero.md`](docs/runbook-point-zero.md) : poste de contrôle,
accès de base des switchs, restauration de pfSense par clé USB, DSM, iLO,
RAID P440, ISO, puis l'enchaînement automatisé.

## Utilisation

Toutes les commandes Ansible se lancent depuis `ansible/`.

```bash
# Avant un rebuild — vérifier le point zéro (lecture seule, verdict à la fin)
ansible-playbook preflight.yml

# Couche 00 — snapshot lecture seule des switchs et de pfSense → build/network/
ansible-playbook 00-network.yml

# Couche 00 — prévisualiser l'application de la config des switchs (doit afficher 0 changement)
ansible-playbook 00-network.yml --tags apply --check --diff --limit l2sw

# Couche 00 — appliquer réellement (après le --check)
ansible-playbook 00-network.yml --tags apply --limit l2sw -e network_apply_confirm=true

# Couche 00 — sauvegarder la config pfSense chiffrée dans le repo (files/pfsense/)
ansible-playbook 00-network.yml --limit pfsense --tags pfsense-backup

# Couche 00 — appliquer alias et règles pfSense as code (prévisualiser avec --check --diff d'abord)
ansible-playbook 00-network.yml --limit pfsense --tags pfsense-apply --check --diff

# Couche 00 — RESTAURER pfSense (écrase la config et redémarre passerelle + VPN)
ansible-playbook 00-network.yml --limit pfsense --tags pfsense-restore -e pfsense_restore_confirm=true

# Couche 10 — lecture seule de l'iLO (aucune modification du serveur)
ansible-playbook 10-bootstrap.yml --limit pve01

# Couche 10 — test de montage/éjection d'ISO (sans reboot, jamais lancé par défaut)
ansible-playbook 10-bootstrap.yml --tags media-test --limit pve01

# Couche 10 — construire un ISO auto-install par hôte (local, Docker requis)
ansible-playbook 10-bootstrap.yml --tags build-iso

# Couche 10 — RÉINSTALLATION (efface le disque système) : nœud vidé, groupe prévenu,
# 10-bootstrap/build/ servi par npx http-server
ansible-playbook 10-bootstrap.yml --tags install --limit pve02 -e pve_install_confirm=true

# Couche 30 — configuration des VMs
ansible-playbook 30-config.yml
```

⚠️ Les serveurs sont en production et le rack est partagé : rien de destructif
(réinstallation, reboot) sans l'accord du groupe.

## Secrets

- `ansible-vault` : `group_vars/<groupe>/vars.yml` en clair, `vault.yml` chiffré.
  Les secrets sont préfixés `vault_` et référencés depuis `vars.yml` ou `host_vars`.
- Mot de passe root Proxmox stocké en clair dans le vault, **haché au rendu**
  de l'`answer.toml` : l'ISO est servi en HTTP et ne doit contenir que le hash.
- Ignorés par git : tfstate, tfvars, ISO, `ansible.log`, fichiers de mot de passe,
  `build/` (configs réseau sauvegardées : hashes, clés), `key/`.

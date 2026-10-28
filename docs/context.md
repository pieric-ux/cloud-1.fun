# context.md — cloud-1-iac

> Doc de passation. Lu en premier par une nouvelle session Claude Code lancée
> dans ce repo. Reprend les décisions prises dans la session précédente (qui
> tournait dans le repo piscine `42-piscine-infra`, dossier différent → ni son
> contexte ni sa mémoire ne suivent ici).

## Le but

**GitOps bare-metal.** Ce repo devient la *source de vérité* de toute l'infra du
rack (42 Lausanne — Piscine Infrastructure, groupe de 3-4 partageant un rack).
Objectif : pouvoir **remonter l'infra entière à partir du repo**, du métal
jusqu'aux VMs, de façon reproductible et versionnée.

C'est une **extension perso** au-delà des modules notés (M00→M06), pas un
livrable de groupe. « Perso d'abord » : prototypé seul, partagé au groupe quand
c'est solide.

## Le mode de travail (IMPORTANT)

**Claude = copilote, pas exécutant.** L'utilisateur (pieric) veut *faire
lui-même* — c'est un piscine, la défense exige d'expliquer et justifier chaque
choix. Donc : Claude explique, débloque, relit le code, donne des pistes de doc.
L'utilisateur tape et construit. Ne pas partir tout coder dans son coin.

- Donner la **direction** (« prochaine étape : X »), pas de commandes basiques
  pas-à-pas (mkdir, touch, git add…). Détailler seulement les vrais pièges et
  les choix à défendre.
- **Ne rien faire sans demande explicite**, y compris les vérifs en lecture
  (git status, ls…) pour « contrôler » l'avancement.

## Les décisions déjà tranchées

| Sujet | Choix |
|---|---|
| Serveur git local | **Gitea/Forgejo** (LXC léger) |
| Sens du miroir | **Local (Gitea) → GitHub** (push-mirror). GitHub = backup + source pour un rebuild from-scratch |
| Automatisation bare-metal | **Oui** : install Proxmox via **Redfish (iLO) + ISO auto-install** |
| Secrets | **ansible-vault + tfvars gitignorés**, tfstate **local gitignoré** |
| Ownership repo | Perso d'abord |

### Le piège chicken-and-egg (à garder en tête)
Le Gitea local tournera dans une VM **sur** Proxmox. Lors d'un rebuild total,
Proxmox n'existe pas encore → Gitea injoignable. Donc **GitHub (ou un clone
laptop) = source de vérité pour le rebuild**. Gitea = remote de travail quotidien
qui push-mirror vers GitHub. Ordre de rebuild :
`clone GitHub → couches 0→3 → la VM Gitea remonte → re-sync avec GitHub`.

## L'architecture — couches et frontières d'outils

Le chaînage est **Packer → (bare metal) → Ansible réseau → Terraform → Ansible config**.
Terraform **ne gère PAS tout** : son vrai terrain = les VMs Proxmox.

| Couche | Quoi | Outil réel | Note |
|---|---|---|---|
| **0. bare metal** | Installer Proxmox sur pve01/pve02 via iLO | **Redfish** (`community.general.redfish_*`) + **ISO Proxmox auto-install** (`answer.toml`, Proxmox 8.2+ `proxmox-auto-install-assistant`) | Terraform ne parle pas à l'iLO |
| **1. réseau** | Switchs Cisco L2/L3 + pfSense | **Ansible** (`cisco.ios`, `pfsensible.core` ou API pfSense) | Providers Terraform Cisco/pfSense immatures → on reste sur Ansible |
| **2. VMs** | Cloner templates Packer, cloud-init, VLAN, disque `synology-lvm` | **Terraform `bpg/proxmox`** (pas Telmate) | ✅ cœur de valeur de Terraform ici |
| **3. config** | users, ssh-hardening, services | **Ansible** (réutiliser les rôles d'`infra04`/`infra06`) | déjà écrits côté piscine |

Ordre impératif à l'exécution (Terraform seul ne sait pas « attends que X
réponde ») → un **Makefile** d'orchestration en racine. Ex : dhcp-dns doit
exister avant les autres VMs ; iSCSI avant toute VM.

## Layout du repo (tranché)

**Un dossier par outil, pas par couche.** Les couches 00/10/30 sont toutes en
Ansible → un seul projet Ansible partagé (inventaire, config, rôles) à la
racine, au lieu de le dupliquer par couche. L'ordre des couches est porté par
le nom des playbooks (`00-`, `10-`, `30-`) et par le Makefile.

```
cloud-1-iac/
├── ansible/                    # projet Ansible partagé (couches 00/10/30)
│   ├── ansible.cfg             # repris tel quel d'infra04
│   ├── requirements.yml        # collections : community.general, cisco.ios, pfsensible.core
│   ├── site.yml                # point d'entrée : import_playbook 00 → 10 → 30
│   ├── 00-bootstrap.yml        # Redfish/iLO → install Proxmox (connection: local)
│   ├── 10-network.yml
│   ├── 30-config.yml           # ex-contenu de site.yml (rôles sur vms:!lxc)
│   ├── inventory/
│   │   ├── zones/              # axe « où » : zones réseau
│   │   │   └── mgmt.yml / dmz.yml / prod.yml   # repris d'infra04 (ansible_host ici)
│   │   ├── baremetal.yml       # axe « quoi » : machines physiques (pve01, pve02)
│   │   ├── vms.yml / lxc.yml   # axe « quoi » : VMs, conteneurs
│   │   ├── network.yml         # switchs L2/L3 + pfSense (couche 10), vide
│   │   ├── group_vars/
│   │   │   ├── all/
│   │   │   │   └── vars.yml    # ex-all.yml, en clair
│   │   │   ├── baremetal/      # à créer : compte iLO (vars.yml + vault.yml chiffré)
│   │   │   └── automation.yml, cyber.yml, dns.yml, …   # inchangés
│   │   └── host_vars/
│   │       └── pve01.yml / pve02.yml   # à créer : ilo_host (couche 00)
│   └── roles/                  # common, users, ssh-hardening, cis-hardening
├── 00-bootstrap/               # hors Ansible : answer.toml(.example), build ISO
├── 20-proxmox/                 # Terraform bpg/proxmox
├── docs/
│   └── context.md              # ce fichier
├── Makefile                    # make bootstrap / network / vms / config
├── .gitignore
└── README.md
```

Pourquoi pas un `ANSIBLE_CONFIG` partagé avec un dossier par couche : les
chemins relatifs (rôles, inventaire) cassent selon le dossier de lancement.

- **Playbooks à la racine d'`ansible/`** (pas de sous-dossier `playbooks/`) :
  à côté de `roles/`, ils trouvent les rôles sans config ; 4 playbooks ne
  justifient pas un dossier.
- **`site.yml` = point d'entrée** (convention Ansible) : uniquement des
  `import_playbook`. Chaque couche reste lançable seule. 00 et 10 sont
  commentés tant qu'ils sont vides (un import de playbook vide échoue).
- **`group_vars/all/` en dossier** : `ansible-vault` chiffre un fichier entier →
  `vars.yml` en clair (grep/diff lisibles), `vault.yml` chiffré. Convention :
  secrets préfixés `vault_`, référencés depuis `vars.yml`
  (`ilo_password: "{{ vault_ilo_password }}"`). Alternative écartée :
  `ansible-vault encrypt_string` dans un seul `all.yml`.
- **Inventaire à deux axes** : `zones/` (mgmt, dmz, prod = *où*, porte les
  `ansible_host`) et fichiers racine `baremetal` / `vms` / `lxc` (= *quoi*,
  ne citent que les noms d'hôtes ; Ansible fusionne → chaque donnée définie
  une seule fois). Dossier nommé `zones/` et pas `network/` pour ne pas
  confondre avec la couche 10.
- **Groupes d'inventaire** : `proxmox` → enfants `pve` (pve01, pve02) et
  `backup` (pbs ; renommé pour éviter un groupe et un hôte de même nom).
  Groupe à part **`baremetal`** (pve01, pve02, listés directement, pas
  `children: pve`) = cible de `00-bootstrap.yml` : on groupe par *ce dont le
  play a besoin* (un iLO, pas d'OS) et non par rôle. `pve` et `baremetal`
  coïncident aujourd'hui, pas forcément demain. Le pbs (VM) n'y est pas.
- **Variables iLO dans `group_vars/baremetal/`**, pas `all/` : seules les
  machines physiques en ont besoin (moindre exposition des secrets).
- Réflexe : `ansible-inventory --graph` après chaque modif d'inventaire (une
  erreur d'indentation fait disparaître des hôtes sans erreur).

### .gitignore minimum (dès le 1er commit)
Terraform écrit des secrets en clair dans le state + ISOs lourds.
```
# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.auto.tfvars
*.tfvars
crash.log
# Secrets
*.vault
vault-password*
*.pem
*.key
*.ovpn
# Artefacts lourds
*.iso
*.img
```
Réflexes défendables : versionner des `terraform.tfvars.example` (sans valeurs
sensibles) ; tfstate local gitignoré (backend propre type Synology/MinIO à voir
plus tard, pas dans le repo).

## Conventions héritées de l'infra existante (repo piscine)

À réutiliser pour rester cohérent (vérifier les valeurs exactes dans
`~/Documents/42-piscine-infra/infra04/ansible/inventory/` avant de s'en servir) :

- **Domaine externe/DNS hosts** : `cloud-1.fun` (ex : `pve01.cloud-1.fun`).
- **Domaine interne** : `infra.lab`.
- **Hyperviseurs** : `pve01`, `pve02` (physiques, iLO 4 firmware 2.82,
  licence Advanced) ; backup : `pbs` = **VM** (couches 20/30, pas 00).
- **Stockage VM partagé** : LVM sur iSCSI Synology, nommé **`synology-lvm`**.
- **Bridge** : `vmbr0` VLAN-aware.
- **VLANs** : Management, Production, Storage, DMZ, VPN.
- **VM de service n°1** : `dhcp-dns` (dnsmasq, domaine `infra.lab`, sur VLAN mgmt
  — vu à `10.1.240.31` dans l'inventaire).
- **Autres hôtes mgmt** déjà dans l'inventaire : `vault` (HashiCorp Vault LXC),
  `rproxy-int`, `ansible`, `grafana`, `prometheus`.
- **Rôles Ansible existants** (`infra04/ansible/roles/`) : `common`,
  `ssh-hardening`, `users`, `cis-hardening`. (`infra06` : `node-exporter`,
  `prometheus`, `grafana`, `alertmanager`, `pve-exporter`, `snmp-exporter`.)
- **Templates Packer existants** : `infra04/packer/` (ubuntu2404, debian13,
  alpine) — base pour la couche 2.

> Le repo piscine reste la **référence** (docs par module, rôles déjà écrits).
> Ici on construit la version *transverse et orchestrée*.

## Où on en est / prochaine étape

- [x] Décisions d'archi tranchées (ci-dessus).
- [x] Dossier `~/Documents/cloud-1-iac` créé + ce `context.md` (dans `docs/`).
- [x] `git init` + `.gitignore` (généré gitignore.io : terraform, ansible,
      packer, macos ; règles projet ajoutées au fur et à mesure — secrets en
      priorité). `.terraform.lock.hcl` volontairement versionné.
- [x] Dossier `ansible/` repris d'`infra04` (inventaire, rôles, cfg, site.yml).
- [x] Restructuration vers le layout ci-dessus (`10-network/` et `30-config/`
      supprimés, `ansible.log` gitignoré,
      `group_vars/all/vars.yml`, `site.yml` → imports, `requirements.yml`).
      `--syntax-check site.yml` et `ansible-inventory --graph` OK.
- [ ] Reste ouvert :
      - `private_key_file=../key/ansible` pointe vers un dossier absent →
        décider où vit la clé (hors repo) ;
      - créer `group_vars/baremetal/vault.yml` (`ansible-vault create`)
        avec les identifiants iLO.
- [x] Inventaire refait (zones/, baremetal, backup) — `ansible-inventory
      --graph` sans warning.
- [x] 1er commit (amend à venir pour inclure l'inventaire).
- [ ] **Couche `00-bootstrap`** ← PROCHAIN GROS MORCEAU : combo Redfish (iLO) +
      ISO Proxmox auto-install. À expliquer avant de coder (demande de pieric).
- [ ] Gitea en LXC + push-mirror GitHub.
- [ ] Couches 10 → 20 → 30, puis Makefile.

### Reprise suggérée pour la nouvelle session
1. Lire ce `context.md`.
2. Régler la clé SSH (pieric tape).
3. `00-bootstrap`, étape 1 = playbook **lecture seule** : cible `baremetal`,
   `connection: local`, `gather_facts: false`, `redfish_info` (Systems,
   Manager/VirtualMedia, actions dispo) + `debug`, testé avec `--limit pve01`.
   Prérequis : `host_vars` pve01/pve02 avec `ilo_host`, compte iLO dédié
   moindre privilège (Virtual Media + Virtual Power and Reset) dans
   `group_vars/baremetal/vault.yml`. Rôle (`redfish_bootstrap`, nommé par ce
   qu'il fait, pas par le groupe) seulement après avoir vu la sortie : un
   fichier de tâches par étape, partie iLO 4 isolée (comme `Debian.yml` /
   `Alpine.yml`), `assert` de confirmation (défaut faux) avant le destructif. iLO 4 : pas d'action
   `InsertMedia` standard → montage par PATCH (`Image` +
   `Oem.Hp.BootOnNextServerReset`), à confirmer par la lecture. Étape 2
   (destructive) séparée + garde-fou, prévenir le groupe (rack partagé).
4. Ordre de rebuild : le pbs (VM) doit remonter tôt (restauration des autres
   VMs) → à placer dans le Makefile / couche 20.
5. Explication Redfish + `answer.toml` déjà donnée. Choix
   encore ouverts : answer embarqué vs servi en HTTP (2 hôtes), qui sert l'ISO
   lors d'un rebuild (laptop/Synology), `root_password_hashed` vs answer
   gitignoré, filtre disque fiable (modèle/serial, pas `sda`).

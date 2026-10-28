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

**Périmètre (tranché) : tout est reconstructible, Synology compris.** Si tout
crashe : on reconfigure toute l'infra par l'automatisation, *puis* on restaure
les backups. Backups = pve02 **+ remote** (copie hors rack → survit à un crash
total).

- **Point zéro manuel** irréductible, à minimiser et documenter en runbook
  dans `docs/` : câblage, IP mgmt des switchs (console), install DSM + 1er
  admin Synology, comptes iLO.
- **Ordre réel de rebuild** : point zéro → réseau → Synology (partage ISO +
  iSCSI) → bare metal pve → VMs → config → restauration backups. La
  numérotation des couches est gardée telle quelle ; l'ordre est porté par le
  Makefile.
- **Ordre de dev ≠ ordre d'exécution** : le réseau existe déjà et marche → on
  finit la couche 00 d'abord, la couche 10 s'insère *avant* elle dans le
  Makefile ensuite.
- **IP des iLO sans config manuelle** : la couche 10 crée des **réservations
  DHCP pfSense** par MAC d'iLO (iLO en DHCP par défaut usine). MAC relevables
  via Redfish `GetManagerNicInventory`. Le compte iLO pourrait aussi être créé
  par Redfish (`AddUser`) avec le mot de passe `Administrator` d'usine
  (étiquette). → point zéro réduit à : IP mgmt des switchs + install DSM.
- **Principe** : automatiser au maximum, documenter le reste avec la raison.
  - `docs/runbook-point-zero.md` (à créer) : étapes manuelles dans l'ordre,
    pour chacune *quoi*, *pourquoi pas automatisable*, *comment vérifier*.
  - **Playbook preflight** lecture seule (à créer) lancé en tête de rebuild :
    vérifie les prérequis manuels (switchs, Synology, iLO + identifiants) et
    stoppe net avec un message clair si un manque. La partie lecture seule de
    `00-bootstrap.yml` en est déjà la moitié.
  - Le runbook rétrécit avec le temps : chaque étape automatisée en sort.
- Synology : pas de collection Ansible officielle → API DSM (`SYNO.*` via
  `uri`) ou SSH + `synowebapi`. À explorer en lecture seule d'abord.

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
- Exception accordée : Claude peut lancer/relancer tout ce qui est **local**
  (rendus, builds, Docker sur le laptop). **Jamais la prod** (OS des pve,
  iLO, VMs, réseau) sans feu vert explicite de pieric.

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
│   ├── ansible.cfg             # repris tel quel d'infra04 (+ vault_password_file)
│   ├── requirements.yml        # collections : community.general, cisco.ios, pfsensible.core
│   ├── site.yml                # point d'entrée : import_playbook 00 → 10 → 30
│   ├── 00-bootstrap.yml        # Redfish/iLO → install Proxmox (connection: local)
│   ├── 10-network.yml
│   ├── 30-config.yml           # ex-contenu de site.yml (rôles sur vms:!lxc)
│   ├── templates/
│   │   └── answer.toml.j2      # answer auto-install Proxmox, rendu par hôte
│   ├── inventory/
│   │   ├── zones/              # axe « où » : zones réseau
│   │   │   └── mgmt.yml / dmz.yml / prod.yml   # repris d'infra04 (ansible_host ici)
│   │   ├── baremetal.yml       # axe « quoi » : machines physiques (pve01, pve02)
│   │   ├── vms.yml / lxc.yml   # axe « quoi » : VMs, conteneurs
│   │   ├── network.yml         # switchs L2/L3 + pfSense (couche 10), vide
│   │   ├── group_vars/
│   │   │   ├── all/
│   │   │   │   └── vars.yml    # ex-all.yml, en clair
│   │   │   ├── baremetal/
│   │   │   │   ├── vars.yml    # ilo_validate_certs, iso_url, pve_install_* communs
│   │   │   │   └── vault.yml   # vault_ilo_password_pveXX, vault_pve_root_password_pveXX
│   │   │   └── automation.yml, cyber.yml, dns.yml, …   # inchangés
│   │   └── host_vars/
│   │       └── pve01.yml / pve02.yml   # iLO + pve_install_* propres à l'hôte
│   └── roles/                  # common, users, ssh-hardening, cis-hardening
├── 00-bootstrap/               # hors Ansible : iso/ (gitignoré), answer.toml, build ISO
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
- **Variables iLO** : l'iLO est un *attribut* de l'hôte (pas un hôte à part :
  une seule identité, `--limit pve01` vise iLO + OS). Comptes différents par
  iLO (`admin_teemo` pve01, `admin_yuumi` pve02) → `ilo_host`, `ilo_user`,
  `ilo_password: "{{ vault_ilo_password_pveXX }}"` dans `host_vars/` ; un
  seul vault de groupe `group_vars/baremetal/vault.yml` (variante choisie
  plutôt qu'un vault par hôte). Rien dans `all/` (moindre exposition).
  `ilo_host` = **IP**, pas un nom DNS (dhcp-dns n'existe pas en rebuild).
- **Mot de passe du vault** : `vault_password_file=~/.ansible/.vault_pass_cloud1`
  dans `ansible.cfg` (hors repo, `600`). Aussi rangé dans Bitwarden.
  Évolution possible : script exécutable qui fait `bw get password`.
- **Valeurs dans le vault** : guillemets simples `'...'` (rien n'y est
  interprété sauf `''`). Si un mot de passe contient `{{` ou `{%` : tag
  `!unsafe` (sinon Ansible le templatise, même entre guillemets).
- Réflexe : `ansible-inventory --graph` après chaque modif d'inventaire (une
  erreur d'indentation fait disparaître des hôtes sans erreur).

### Prérequis de la machine de contrôle (laptop)
Repris dans le `README.md`.
- Ansible via pipx + **`pipx inject ansible passlib`** (filtre `password_hash`
  sous Python 3.13+, le module `crypt` a disparu).
- Collections : `ansible-galaxy collection install -r ansible/requirements.yml`.
- Fichier de mot de passe du vault `~/.ansible/.vault_pass_cloud1` (`600`).
- Clé SSH automation (emplacement **à décider**, hors repo ; en attendant :
  `--private-key ~/Documents/42-piscine-infra/infra04/key/ansible`).
- Node/npx (`npx http-server` pour servir l'ISO, Range requis).
- Docker (conteneur Debian pour `proxmox-auto-install-assistant`).

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

## Couche 00 — constats et choix

**Réglages du play `00-bootstrap.yml`** (`hosts: baremetal`) :
- `connection: local` : l'iLO (BMC) n'a ni shell ni Python → le module tourne
  sur le laptop et agit en client HTTPS. Pas de délégation à la VM `ansible` :
  elle n'existe pas en rebuild.
- `become: false` : sinon le `become=True` du cfg tente un sudo sur le Mac.
- `ansible_python_interpreter: "{{ ansible_playbook_python }}"` dans les
  `vars` du play (l'auto-discovery a pris un shim pyenv cassé). Au niveau du
  play, **pas** dans `group_vars/baremetal` : ces hôtes sont aussi joints en
  SSH par les couches suivantes.

**Résultats de la lecture Redfish** (pve01 + pve02, identiques sauf mention) :
- iLO : `10.1.240.21` (pve01), `10.1.240.22` (pve02). ≠ IP de l'OS
  (`.11` / `.12`) — erreur initiale « Connection refused » = IP de l'OS.
- DL380 Gen9, iLO 4 **v2.82**, 256 Go. BIOS P89 v3.30 (pve01) / v3.40 (pve02).
  CPU différents (E5-2680 v3 / E5-2620 v4).
- Média virtuel CD/DVD = **`/redfish/v1/Managers/1/VirtualMedia/2/`**.
- **Pas** d'action standard `#VirtualMedia.InsertMedia` → uniquement
  `Oem.Hp` : `#HpiLOVirtualMedia.InsertVirtualMedia` (param `Image`) et
  `EjectVirtualMedia`. → montage par **`uri` POST** sur la cible de l'action.
  Champ `Inserted` pour l'idempotence ; `Oem.Hp.BootOnNextServerReset` présent.
- Boot : `Cd` dans `BootSourceOverrideSupported`. Méthode **tranchée : HPE
  `BootOnNextServerReset`** (même ressource que le montage, remis à false par
  l'iLO après le boot). Standard `Boot Once Cd` = futur fichier iLO 5.
- Reboot : action standard `ComputerSystem.Reset` dispo.
- **Serveurs hétérogènes** : disques sur contrôleur slot 1 (pve01,
  `HD.Slot.1.x`) vs intégré (pve02, `HD.Emb.1.x`) ; NICs en slots 4/6 vs 4/5
  → disque cible et interface **différents par hôte** dans `answer.toml`.
- `SerialNumber` **vide** → impossible d'identifier les hôtes par serial
  (answer HTTP) → passer par la MAC.

**Servir l'ISO** : l'iLO lit par requêtes HTTP **Range** → `python3 -m
http.server` ne marche pas. Choix : **`npx http-server` sur le laptop**,
joignable par les iLO. `iso_url` en variable (`group_vars/baremetal`) pour
pouvoir changer de serveur sans toucher au playbook. GUI iLO (console
distante) = dépannage seulement (manuel, lié à la session).

**ISO** : Proxmox VE **9.2** dans `00-bootstrap/iso/` (gitignoré). Clés
`answer.toml` en **kebab-case** en 9.x (`root-password-hashed`, …) → suivre
le wiki « Automated Installation » 9.x. `proxmox-auto-install-assistant`
= paquet Debian → conteneur Debian ou Proxmox, pas macOS.

**Packer : pas pour l'ISO.** Packer produit des images de VM, pas un ISO
d'install modifié, et n'a pas de builder bare metal ; une image disque
commune casserait sur des serveurs hétérogènes. Il reste à la couche 20
(templates VM). L'ISO = `proxmox-auto-install-assistant prepare-iso` dans un
conteneur Debian (Dockerfile dans `00-bootstrap/`), **un ISO par hôte**
avec answer embarqué (plus simple que le mode HTTP, qui exige un serveur de
réponses capable de traiter un POST).

**Relevé sur les nœuds** (SSH lecture seule, 2026-10-28) :
- PVE 9.2.21, **UEFI**, ext4 sur LVM (`pve-root` sur `sda3`), clavier `us`,
  `Europe/Zurich`, DNS `10.1.240.31` + `208.67.222.222`, search `cloud-1.fun`.
- Disque système = `sda`, volume logique Smart Array 136,7 Go
  (`ID_MODEL=LOGICAL_VOLUME`). **`sdb`/`sdc` = LUN iSCSI partagé 1 To**
  (Synology, multipath `dm-6`) → ne jamais le cibler.
- Réseau : `bond0` = nic0-3 LACP (802.3ad, layer2+3) → `vmbr0` VLAN-aware
  (vids 10 20 30 240) ; mgmt = **`vmbr0.240`** (`10.1.240.1x/24`, gw
  `10.1.240.1`) ; `vmbr0.20` (`10.1.20.1x/24`) ; `bond1` = nic4-7 LACP MTU
  9000, `10.1.230.1`/`.2` /30 (lien direct pve01↔pve02).

**`answer.toml`** = template `ansible/templates/answer.toml.j2` (clés 9.x),
valeurs communes dans `group_vars/baremetal/vars.yml`, propres à l'hôte dans
`host_vars/`. Rendu validé (TOML OK) pour les 2 hôtes.
- Disque : `filter.ID_SERIAL` = ID exact du volume logique de chaque hôte.
  Introuvable → l'install **s'arrête** au lieu de prendre un autre disque.
- Réseau : `from-answer`, IP mgmt sur nic0 (filtre `ID_NET_NAME_MAC`, MAC
  permanente). ⚠️ **Le vrai réseau (bond LACP + VLAN 240 tagué) n'est pas
  exprimable dans l'answer** → nic0 seul en non tagué ne sera sans doute pas
  joignable. À appliquer dès le 1er boot : **hook first-boot**
  (`prepare-iso --on-first-boot`) généré par hôte (interfaces complet, avec
  `bond1` et `vmbr0.20`).
- `root-ssh-keys` = `users_automation_keys` (Ansible joint le nœud neuf).
- **Mot de passe root** : différent par nœud. **En clair dans le vault**
  (`vault_pve_root_password_pve01/02`, même valeur que Bitwarden), **haché au
  rendu** : `password_hash('sha512', pve_install_root_password_salt)`. Raison :
  l'ISO est servi en HTTP sans auth → il ne doit porter que le hash ; le
  vault ne protège plus rien une fois l'ISO généré. **Sel fixe par hôte**
  (pas secret, dans `host_vars`) → answer identique d'un run à l'autre
  (vérifié : même empreinte sur 2 rendus). passlib ajoute `rounds=656000`.

**Hook first-boot** (`ansible/templates/first-boot.sh.j2`, `ordering =
"before-network"`) : écrit le vrai `/etc/network/interfaces` (bond0 LACP →
vmbr0 VLAN-aware, vmbr0.240 mgmt, vmbr0.20 storage, bond1 MTU 9000). NICs
retrouvées par **MAC permanente** (`pve_net_bond0_macs` / `_bond1_macs` en
`host_vars`) → nommage des interfaces indifférent. Testé sur un faux `/sys` :
reproduit la config actuelle ; MAC absente → exit 1. Piège corrigé : avec
plusieurs `$(...)` dans une affectation, `set -e` ne voit que le dernier.
Si le hook échoue : config simple de l'installeur → nœud sans doute
injoignable → récupération par la console iLO.

**Build ISO** (`--tags build-iso`, local, tag `never`) : rendu answer (`0600`)
+ hook dans `00-bootstrap/build/<hôte>/` (gitignoré) → `validate-answer` →
`prepare-iso` dans le conteneur (`00-bootstrap/Dockerfile`, debian trixie +
dépôt Proxmox, `--platform linux/amd64`). Reconstruit seulement si answer ou
hook changent. Pièges de `prepare-iso` : il copie l'ISO source **à côté
d'elle** (→ `--tmp /work`, le dossier ISO étant monté en lecture seule) et
**sort en code 0 même en échec** (→ tâche qui vérifie que l'ISO existe).
Les 2 ISO sont construits et inspectés (answer.toml, `mode = "iso"`,
`proxmox-first-boot` présents).

**Install** (play 2 de `00-bootstrap.yml`, DESTRUCTIF) : tag `never, install`
au niveau du play (0 tâche en run par défaut, vérifié) + `assert
pve_install_confirm` (faux par défaut) → il faut **à la fois** `--tags install`
et `-e pve_install_confirm=true`. `serial: 1` + `any_errors_fatal` : un nœud à
la fois, arrêt total si un échoue. Déroulé : HEAD sur l'ISO préparé → éjection
éventuelle → montage → PATCH `BootOnNextServerReset: true` → assert → reset
(cible lue dans `Systems/1` `Actions`, `ForceRestart` ou `On`) → attendre que
8006 tombe **puis** revienne (sinon on validerait l'ancien nœud) → éjection →
suppression de l'ancienne clé d'hôte SSH. `rescue` : si échec **avant** le
reset, désarme le boot et éjecte ; **après**, ne touche à rien (l'installeur
lit peut-être l'ISO). ISO préparé servi depuis `00-bootstrap/build/` via
`pve_install_iso_url` (jamais depuis `iso/`). **Pas encore lancé : test prévu
en fin de lab** (nœud vidé, groupe prévenu).

**Prudence (serveurs en prod, rack partagé)** : ne rien faire qui modifie ou
crashe les serveurs sans accord du groupe. Monter un ISO sans reboot = lecteur
USB branché à chaud, sans impact ; seul risque = reboot imprévu pendant le
montage → éjecter immédiatement, vérifier l'ordre de boot (`GetBootOrder`)
avant. Tests de montage avec l'**ISO de base** (installeur interactif,
n'efface rien), jamais avec l'ISO préparé (s'installe seul et efface).

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
- [x] Inventaire refait (zones/, baremetal, backup) — `ansible-inventory
      --graph` sans warning.
- [x] 1er commit (amend à venir pour inclure l'inventaire).
- [x] Accès iLO : `host_vars` pve01/pve02, vault de groupe, fichier de mot de
      passe du vault.
- [x] `00-bootstrap.yml` **lecture seule** (`redfish_info` Systems/Manager +
      `uri` GET brut VirtualMedia/2 et Systems/1) — OK sur pve01 et pve02.
- [ ] Reste ouvert : `private_key_file=../key/ansible` pointe vers un dossier
      absent → décider où vit la clé (hors repo).
- [x] **Couche 00, étape 2** : ISO servi par `npx http-server` (laptop
      `10.1.240.111`, même sous-réseau mgmt que les iLO → pas de routage),
      Range vérifié (206). `iso_url` dans `group_vars/baremetal/vars.yml`.
      Bloc montage/éjection dans `00-bootstrap.yml`, tag `never, media-test`
      (jamais exécuté par défaut), éjection en `always`, assert
      `BootOnNextServerReset` false. **Testé OK sur pve02** (monté + éjecté,
      aucun impact). Constat : l'iLO 4 fait un `GET <iso>` au montage et un
      `GET <iso>?EJECT` à l'éjection (User-Agent vide).
- [x] Couche 00, étape 3 (partiel) : méthode de boot tranchée (HPE),
      template `answer.toml.j2` + variables par hôte, mot de passe root haché
      au rendu (passlib installé), rendu validé.
- [x] Couche 00, étape 3 : hook first-boot réseau, build ISO par hôte
      (`--tags build-iso`), answer validé par l'outil officiel, 2 ISO construits.
- [x] Couche 00, étape 4 : play d'install destructif écrit (`never, install` +
      confirmation). **Non exécuté** — test en fin de lab.
- [ ] Gitea en LXC + push-mirror GitHub.
- [ ] Synology dans le périmètre (partage ISO + iSCSI) — exploration API.
- [ ] Couches 10 → 20 → 30, puis Makefile.

### Reprise suggérée pour la nouvelle session
1. Lire ce `context.md`.
2. Couche 00 écrite de bout en bout ; seul reste le **test réel de l'install
   en fin de lab** : vider un nœud, prévenir le groupe, servir
   `00-bootstrap/build/` en npx, `--tags install --limit pveXX -e
   pve_install_confirm=true`. Points à observer : hook réseau appliqué,
   cluster/iSCSI à refaire après (couche suivante).
3. En attendant : couche 10 (pfSense + switchs, dont réservations DHCP des
   iLO), runbook point zéro, playbook preflight.
6. Passage en rôle `redfish_bootstrap` (nommé par ce qu'il fait) une fois les
   étapes connues : un fichier de tâches par étape, partie iLO 4 isolée
   (comme `Debian.yml` / `Alpine.yml`), `assert` de confirmation (défaut
   faux) avant le destructif.
7. Ordre de rebuild : le pbs (VM) doit remonter tôt (restauration des autres
   VMs) → Makefile / couche 20.

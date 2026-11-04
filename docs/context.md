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
  finit la couche 10 d'abord, la couche 00 s'insère *avant* elle dans le
  Makefile ensuite.
- **IP des iLO : statiques, point zéro** (idée de réservations DHCP pfSense
  abandonnée). Le DHCP du VLAN MGMT est servi par la VM `dhcp-dns` (dnsmasq),
  absente en rebuild ; et l'IP est stockée dans l'iLO lui-même → elle survit
  à la réinstallation de l'OS. À faire une fois par machine. MAC iLO :
  `94:18:82:74:4b:b0` (pve01), `f4:03:43:41:a1:dc` (pve02). Le compte iLO
  pourrait être créé par Redfish (`AddUser`) avec le mot de passe
  `Administrator` d'usine (étiquette).
- **Principe** : automatiser au maximum, documenter le reste avec la raison.
  - `docs/runbook-point-zero.md` (**écrit le 2026-10-29**) : étapes manuelles dans l'ordre,
    pour chacune *quoi*, *pourquoi pas automatisable*, *comment vérifier*.
  - **Playbook preflight** lecture seule (**fait le 2026-10-29** : rôle
    `preflight`, `preflight.yml`) lancé en tête de rebuild :
    vérifie les prérequis manuels (switchs, Synology, iLO + identifiants) et
    stoppe net avec un message clair si un manque. La partie lecture seule de
    `10-bootstrap.yml` en est déjà la moitié.
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
│   ├── 10-bootstrap.yml        # appels du rôle redfish_bootstrap (connection: local)
│   ├── 00-network.yml          # appels des rôles ios_switch et pfsense
│   ├── 30-config.yml           # ex-contenu de site.yml (rôles sur vms:!lxc)
│   ├── inventory/
│   │   ├── zones/              # axe « où » : zones réseau
│   │   │   └── mgmt.yml / dmz.yml / prod.yml   # repris d'infra04 (ansible_host ici)
│   │   ├── baremetal.yml       # axe « quoi » : machines physiques (pve01, pve02)
│   │   ├── vms.yml / lxc.yml   # axe « quoi » : VMs, conteneurs
│   │   ├── network.yml         # network → switches (l3sw, l2sw) + firewall (pfsense), IP ici
│   │   ├── group_vars/
│   │   │   ├── all/
│   │   │   │   └── vars.yml    # ex-all.yml, en clair
│   │   │   ├── baremetal/
│   │   │   │   ├── vars.yml    # ilo_validate_certs, iso_url, pve_install_* communs
│   │   │   │   └── vault.yml   # vault_ilo_password_pveXX, vault_pve_root_password_pveXX
│   │   │   ├── switches/       # network_cli, paramiko, admin ; vault = mdp par switch
│   │   │   ├── firewall/       # pfSense admin ; vault = mdp pfSense
│   │   │   ├── proxmox.yml / vms.yml / lxc.yml   # ansible_ssh_private_key_file
│   │   │   └── automation.yml, lab.yml, dns.yml, …   # inchangés
│   │   └── host_vars/
│   │       ├── pve01.yml / pve02.yml   # iLO + pve_install_* propres à l'hôte
│   │       └── l2sw/ / l3sw/   # vars.yml (mdp → vault, particularités IOS)
│   │                           # + ios_resources.yml (config du switch as code)
│   └── roles/
│       ├── redfish_bootstrap/  # couche 10 : probe, media_test, build_iso, install ; ilo4/
│       ├── ios_switch/         # couche 00 : snapshot, parse, apply (resources | rendered)
│       ├── pfsense/            # couche 00 : snapshot (config.xml)
│       └── common, users, ssh-hardening, cis-hardening   # couche 30 (infra04)
├── 10-bootstrap/               # hors Ansible : Dockerfile, iso/ et build/ (gitignorés)
├── 20-proxmox/                 # Terraform bpg/proxmox
├── build/                      # gitignoré : snapshots réseau (build/network/<hôte>/)
├── key/                        # gitignoré : clé SSH automation (ansible, ansible.pub)
├── docs/
│   └── context.md              # ce fichier
├── Makefile                    # make bootstrap / network / vms / config
├── .gitignore
└── README.md
```

Pourquoi pas un `ANSIBLE_CONFIG` partagé avec un dossier par couche : les
chemins relatifs (rôles, inventaire) cassent selon le dossier de lancement.

- **Renumérotation (2026-10-29)** : les numéros suivent l'ordre d'exécution
  → `00-network` (switchs + pfSense) puis `10-bootstrap` (bare metal), car
  iLO, NAS et hyperviseurs dépendent du réseau. `git mv` (historique
  conservé) du dossier `10-bootstrap/` (ex-`00-…`) et des deux playbooks ;
  chemins (`pve_iso_source`, `pve_iso_build_dir`, contexte Docker), imports
  de `site.yml` (réordonnés) et docs mis à jour. Trous de 10 en 10 pour
  insérer une couche (Synology → `05-storage`). Dans ce fichier, les numéros
  ont été convertis au nouveau schéma (les messages de commit gardent
  l'ancien).
- **Playbooks à la racine d'`ansible/`** (pas de sous-dossier `playbooks/`) :
  à côté de `roles/`, ils trouvent les rôles sans config ; 4 playbooks ne
  justifient pas un dossier.
- **Playbooks = aiguillages, toute la logique dans des rôles** (refactor du
  2026-10-29). Rôles créés avec `ansible-galaxy role init` (cohérent avec les
  rôles d'infra04), README réel par rôle, `tasks/main.yml` = l'action sans
  danger (lecture seule). Une action par fichier de tâches, appelée par
  `import_role` + `tasks_from` + tag. **`roles:` au niveau du play ignore
  `tasks_from`** (testé : il lance `main.yml`) → `import_role` est la façon
  documentée d'appeler un point d'entrée précis. **Même syntaxe partout** :
  `30-config.yml` (ex-`site.yml` d'infra04, en `roles:`) converti aussi en
  `import_role` (comportement identique : statique, tags et handlers
  importés ; `--list-tasks` identique avant/après, 25 tâches). Tâches incluses
  dynamiquement : `include_tasks` + `apply: {tags: [always]}`, sinon elles
  sont filtrées par `--tags`.
  - `redfish_bootstrap` : `probe`, `media_test`, `build_iso`, `install` ;
    appels propres au BMC dans `tasks/<redfish_vendor>/` (`ilo4/` :
    media_state, media_insert, media_eject, boot_once), réutilisés par
    media_test et install (plus de duplication). iLO 5 = un dossier de plus.
    Templates `answer.toml.j2` et `first-boot.sh.j2` dans le rôle.
    `module_defaults` (identifiants iLO pour `uri`) dans le playbook.
  - `ios_switch` : `snapshot` (écrit aussi `ios_resources.yml` *proposé*
    dans `build/` → diff avec les host_vars pour voir une modif faite à la
    main), `parse` (hors ligne, cible 127.0.0.1), `apply` →
    `apply_resources` | `apply_rendered`. Transformation brut → host_vars =
    filtre versionné `filter_plugins/ios_resources.py`
    (`ios_resources_prune`, `ios_vlans_from_config`) : reproduit à
    l'identique les host_vars commités (vérifié).
  - `pfsense` : `snapshot` (config.xml) ; pfsensible.core ensuite.
  - Validation du refactor : local (filtre identique, garde-fou install,
    build-iso inchangé à l'octet, candidat l3sw identique) puis prod en
    lecture seule (snapshots = host_vars, `apply --check` = 0 changement
    sur les 2 switchs, probe iLO pve01 + pve02).
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
  confondre avec la couche 00.
- **Groupes d'inventaire** : `proxmox` → enfants `pve` (pve01, pve02) et
  `backup` (pbs ; renommé pour éviter un groupe et un hôte de même nom).
  Groupe à part **`baremetal`** (pve01, pve02, listés directement, pas
  `children: pve`) = cible de `10-bootstrap.yml` : on groupe par *ce dont le
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
- Clé SSH automation dans **`key/`** (gitignoré, `700`/`600`), copiée depuis
  le repo piscine ; à remettre à la main sur une machine neuve (runbook).
- **`pipx inject ansible ansible-pylibssh 'paramiko<4'`** : les switchs (IOS
  12.2 / 15.2) n'offrent que du kex SHA-1 ; la libssh embarquée dans
  pylibssh est compilée sans, paramiko ≥ 4 l'a retiré → **paramiko 3.5**.
- Collection `pfsensible.core` (dans `requirements.yml`).
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

## Couche 10 — constats et choix

**Réglages du play `10-bootstrap.yml`** (`hosts: baremetal`) :
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

**RAID des P440 — non couvert par le code (constaté le 2026-10-29, À FAIRE)**.
Lu en lecture seule via Redfish (`/redfish/v1/Systems/1/SmartStorage/ArrayControllers/`,
liens HAL `links.*.href` sur iLO 4 ; identifiant du contrôleur différent selon
l'hôte → passer par la liste `Members`) :

| | pve01 | pve02 |
|---|---|---|
| Contrôleur | Smart Array P440, slot 1, fw 7.00, cache 4 Go | Smart Array P440ar intégré, slot 0, fw 7.00, cache 2 Go |
| Volume | RAID 1, 139 979 Mio, stripe 256 Kio | RAID 1, 139 979 Mio, stripe 256 Kio |
| Disques | 2 × 146 Go SAS 15k, `1I:1:17` + `1I:1:18` | 2 × 146 Go SAS 15k, `1I:3:1` + `1I:3:2` |
| VolumeUniqueIdentifier | `600508B1001CB60EB8325EF6DA69C87A` | `600508B1001C400589558BA5BEF164EE` |

L'identifiant = `pve_install_disk_serial` de l'answer (Linux préfixe `3`, minuscules) :
le bootstrap cible bien ce volume. La config RAID vit sur le contrôleur et les
disques : elle survit aux réinstallations, perdue seulement si disques/contrôleur
remplacés ou array effacé → l'install s'arrête (filtre disque introuvable).
Pas automatisable proprement sur Gen9 : SmartStorage en **lecture seule** sur
iLO 4 (config RAID par Redfish = iLO 5 / Gen10) ; création via `ssacli` (OS
lancé) ou HPE SSA (F10) seulement.
**Fait (2026-10-29)** : RAID attendu en `host_vars` (`pve_raid` : modèle de
contrôleur, niveau, stripe, baies) ; vérification Redfish en lecture seule
`redfish_bootstrap/tasks/raid_check.yml` (+ `ilo4/raid_state.yml`) lancée par
le `probe` et **en tête d'`install`** (après confirmation, avant toute action
sur l'iLO) : contrôleur, santé, volume dont l'identifiant ==
`pve_install_disk_serial`, RAID 1, stripe, baies, disques sains. OK sur les 2
hôtes ; cas d'échec testé (identifiant faux → arrêt avec état réel/attendu).
**Reste à faire** : la création elle-même, manuelle (runbook point zéro) :
`ssacli ctrl slot=1 create type=ld drives=1I:1:17,1I:1:18 raid=1 ss=256`
(pve01), `slot=0` + `1I:3:1,1I:3:2` (pve02), ou HPE SSA (F10), puis **mettre
à jour `pve_install_disk_serial`** (nouveau volume = nouvel identifiant).

**Servir l'ISO** : l'iLO lit par requêtes HTTP **Range** → `python3 -m
http.server` ne marche pas. Choix : **`npx http-server` sur le laptop**,
joignable par les iLO. `iso_url` en variable (`group_vars/baremetal`) pour
pouvoir changer de serveur sans toucher au playbook. GUI iLO (console
distante) = dépannage seulement (manuel, lié à la session).

**ISO** : Proxmox VE **9.2** dans `10-bootstrap/iso/` (gitignoré). Clés
`answer.toml` en **kebab-case** en 9.x (`root-password-hashed`, …) → suivre
le wiki « Automated Installation » 9.x. `proxmox-auto-install-assistant`
= paquet Debian → conteneur Debian ou Proxmox, pas macOS.

**Packer : pas pour l'ISO.** Packer produit des images de VM, pas un ISO
d'install modifié, et n'a pas de builder bare metal ; une image disque
commune casserait sur des serveurs hétérogènes. Il reste à la couche 20
(templates VM). L'ISO = `proxmox-auto-install-assistant prepare-iso` dans un
conteneur Debian (Dockerfile dans `10-bootstrap/`), **un ISO par hôte**
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

**`answer.toml`** = template `roles/redfish_bootstrap/templates/answer.toml.j2` (clés 9.x),
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

**Hook first-boot** (`roles/redfish_bootstrap/templates/first-boot.sh.j2`, `ordering =
"before-network"`) : écrit le vrai `/etc/network/interfaces` (bond0 LACP →
vmbr0 VLAN-aware, vmbr0.240 mgmt, vmbr0.20 storage, bond1 MTU 9000). NICs
retrouvées par **MAC permanente** (`pve_net_bond0_macs` / `_bond1_macs` en
`host_vars`) → nommage des interfaces indifférent. Testé sur un faux `/sys` :
reproduit la config actuelle ; MAC absente → exit 1. Piège corrigé : avec
plusieurs `$(...)` dans une affectation, `set -e` ne voit que le dernier.
Si le hook échoue : config simple de l'installeur → nœud sans doute
injoignable → récupération par la console iLO.

**Build ISO** (`--tags build-iso`, local, tag `never`) : rendu answer (`0600`)
+ hook dans `10-bootstrap/build/<hôte>/` (gitignoré) → `validate-answer` →
`prepare-iso` dans le conteneur (`10-bootstrap/Dockerfile`, debian trixie +
dépôt Proxmox, `--platform linux/amd64`). Reconstruit seulement si answer ou
hook changent. Pièges de `prepare-iso` : il copie l'ISO source **à côté
d'elle** (→ `--tmp /work`, le dossier ISO étant monté en lecture seule) et
**sort en code 0 même en échec** (→ tâche qui vérifie que l'ISO existe).
Les 2 ISO sont construits et inspectés (answer.toml, `mode = "iso"`,
`proxmox-first-boot` présents).

**Install** (play 2 de `10-bootstrap.yml`, DESTRUCTIF) : tag `never, install`
au niveau du play (0 tâche en run par défaut, vérifié) + `assert
pve_install_confirm` (faux par défaut) → il faut **à la fois** `--tags install`
et `-e pve_install_confirm=true`. `serial: 1` + `any_errors_fatal` : un nœud à
la fois, arrêt total si un échoue. Déroulé : HEAD sur l'ISO préparé → éjection
éventuelle → montage → PATCH `BootOnNextServerReset: true` → assert → reset
(cible lue dans `Systems/1` `Actions`, `ForceRestart` ou `On`) → attendre que
8006 tombe **puis** revienne (sinon on validerait l'ancien nœud) → éjection →
suppression de l'ancienne clé d'hôte SSH. `rescue` : si échec **avant** le
reset, désarme le boot et éjecte ; **après**, ne touche à rien (l'installeur
lit peut-être l'ISO). ISO préparé servi depuis `10-bootstrap/build/` via
`pve_install_iso_url` (jamais depuis `iso/`). **Pas encore lancé : test prévu
en fin de lab** (nœud vidé, groupe prévenu).

**Prudence (serveurs en prod, rack partagé)** : ne rien faire qui modifie ou
crashe les serveurs sans accord du groupe. Monter un ISO sans reboot = lecteur
USB branché à chaud, sans impact ; seul risque = reboot imprévu pendant le
montage → éjecter immédiatement, vérifier l'ordre de boot (`GetBootOrder`)
avant. Tests de montage avec l'**ISO de base** (installeur interactif,
n'efface rien), jamais avec l'ISO préparé (s'installe seul et efface).

## Couche 00 — constats et choix

**Équipements** (repo piscine `infra01/vlan_ip_plan.md`, `infra/other_equipment_notes.md`) :

| Hôte | Modèle | IP mgmt | OS |
|---|---|---|---|
| l3sw | Catalyst 3560-V2 `WS-C3560V2-48PS`, passerelle de tous les VLAN | `10.1.240.1` (transit `10.1.255.1`) | IOS **12.2(55)SE12** ipservicesk9 |
| l2sw | Catalyst 2960-X `WS-C2960X-48LPS-L` | `10.1.240.2` | IOS **15.2(7)E9** universalk9 |
| pfsense | mini PC N100, pfSense CE 2.7.2 | `10.1.255.2` (admin `192.168.99.1`) | FreeBSD |
| wifi-ap | Aironet 1602I autonome | `10.1.240.3` | hors périmètre pour l'instant |

VLAN : 10 PROD, 20 STOR, 30 DMZ, 240 MGMT, 999 BLACKHOLE (le 1000 VPN de la doc
n'existe pas sur les switchs → écart doc à corriger). l3sw : `ip routing`, 5
SVI, route par défaut → pfSense `10.1.255.2`, `ip helper-address 10.1.240.31`.

**Connexion Ansible aux switchs** (`network_cli`, mot de passe du vault, un
par switch dans `host_vars/l2sw.yml` / `l3sw.yml`) — pièges résolus :
- Kex SHA-1 uniquement → `ansible_network_cli_ssh_type: paramiko` + paramiko
  3.5 (l'option `ansible_libssh_key_exchange_algorithms` est ignorée : libssh
  embarquée compilée sans SHA-1).
- **`private_key_file` retiré d'`ansible.cfg`** (commenté avec la raison) :
  `network_cli` reprend *directement* la clé du cfg (play_context, l. 525 de
  `network_cli.py`) quelles que soient les variables ; paramiko la présente,
  le Cisco refuse puis coupe (`expected packet type 50, got 5`, bug connu)
  avant le mot de passe. → clé déclarée par groupe Linux
  (`group_vars/proxmox.yml`, `vms.yml`, `lxc.yml` : `ansible_ssh_private_key_file`).
- Clé RSA d'admin retirée du `pubkey-chain` de l2sw (nettoyage pieric). Piste
  « clés par personne » abandonnée : IOS 12.2/15.2 = `ssh-rsa` seulement, nos
  clés sont ed25519. On reste au mot de passe.
- ~8 échecs d'auth sur l2sw le 2026-10-28 soir (tests) : visibles dans son log.

**`00-network.yml` étape 1 (lecture seule, OK sur les 2 switchs)** :
`ios_facts` + `gather_network_resources` (liste `ios_snapshot_resources` en
group_vars, surchargée par hôte) + `show running-config` →
`build/network/<hôte>/` (gitignoré, `0600`). pfSense : copie de
`/cf/conf/config.xml` → **timeout SSH** (`10.1.255.2:22`) : SSH désactivé,
règle pare-feu, ou écoute sur le port d'admin seulement → à débloquer.

**IOS 12.2 du l3sw** : pas de filtre `| section` → tous les parseurs live de
`cisco.ios` échouent → `ios_snapshot_resources: []`, running-config seule,
puis conversion **hors ligne** (`state: parsed`, cible `127.0.0.1` pour ne
jamais toucher le switch ; `ios_vlans` et `ios_lacp_interfaces` tentent
quand même une connexion → VLAN extraits par regex). Pour appliquer :
`state: rendered` + `ios_config` (mode `ios_apply_mode: rendered` par hôte,
`resources` par défaut) ; même format YAML pour les 2 switchs, seul
l'adaptateur change. Limite : `ios_config` n'enlève pas → `no …` explicite.
- Mise à jour IOS étudiée puis **abandonnée** : 15.0(2)SE11 existe pour le
  3560-V2 (ipbasek9 suffirait : aucune fonction IP Services utilisée) mais
  « Service Contract Required » ; pas de source officielle. Flash 28 Mo, 11,2
  libres (image actuelle = dossier, installée par `.tar`). Si un jour :
  `.bin`, même plateforme `c3560-` (pas `c3560e-`/`c3560c-` → ROMMON), SHA-512
  Cisco vérifié sur le Mac + MD5 sur le switch, jamais de reboot avant
  `verify` + `show boot`, fenêtre annoncée (coupure de tout le rack).
- **Faille critique Smart Install (CVE-2018-0171)** : touche aussi la 15.0 →
  se corrige par config (`no vstack`). **Vérifié le 2026-10-28 : désactivé
  sur les 2 switchs** (l3sw `Oper Mode: Disabled` + `no vstack` déjà en
  config ; l2sw rien d'actif). `no vstack` à mettre explicitement dans la
  config gérée des 2 (garantie après rebuild). Durcissement à prévoir : `no ip http server` / `secure-server`,
  `access-class` sur les vty (SSH depuis MGMT seulement), SNMPv3.
- Dette technique assumée : 3560-V2 en fin de vie → remplacement par un
  Catalyst IOS-XE (3650/9300) recommandé à terme.
- **Config complète + durcissement (2026-10-29)** : audit running-config vs
  code → tout ce qui sort des modules de ressources (services, SSH, NTP, VTP,
  STP dont la priorité racine du l3sw, `ip routing`, `ip default-gateway`,
  line con/vty, SNMP, enable secret, admin, interface-range, traps) ajouté en
  `ios_global_config` (groupe) / `ios_global_config_host` (hôte), appliqué
  par `apply_global.yml` (`ios_config`). Secrets (hashes enable/admin,
  communauté SNMP) ajoutés au vault des switchs (même mot de passe de vault).
  Hors code : lignes générées par l'IOS (version, boot markers, provision,
  trustpoint autosigné, ntp clock-period, défauts affichés). Durcissement
  ajouté et **appliqué** : `no ip redirects`/`unreachables` sur `Vlan240`,
  tcp-keepalives in/out, `no ip source-route`, `ip ssh time-out 60`. Pièges :
  `no vstack` n'existe plus en 15.2(7)E (Smart Install retiré) → l3sw seul ;
  `ip ssh authentication-retries 3` = défaut jamais affiché → retiré.
  **`write memory` manquait** : handler `Save switch config` notifié par
  toute tâche qui modifie (configs sauvegardées). `--check` = 0, snapshots =
  code. ⚠️ Communauté SNMP et hashes enable affichés dans la session lors de
  l'audit (lab : non bloquant ; l3sw en MD5).

**VTP → transparent (fait le 2026-10-28, sans coupure)** : l2sw (client) puis
l3sw (serveur), `write memory`. Les VLAN sont dans la running-config des 2
switchs, identiques. **Ansible remplace VTP** comme distributeur de VLAN
(VTP : risque d'écrasement du domaine par un switch à révision plus haute).

**Sauvegarde auto des configs** : plus tard avec **Oxidized** (LXC, versionne
dans git, diff, gère aussi pfSense). Les sauvegardes contiennent des secrets
→ dépôt séparé privé ou chiffré, jamais ce repo en clair.

**pfSense** : commencer par la **restauration du `config.xml`** (chiffré par
le vault) pour savoir reconstruire, puis `pfsensible.core` objet par objet
(alias, règles, NAT ; OpenVPN en dernier).
- **Accès SSH débloqué (2026-10-29)** : SSH en *Public Key Only* →
  `key/ansible.pub` ajoutée aux *Authorized SSH Keys* d'`admin` (la clé de
  benedict a été retirée à cette occasion : à confirmer avec lui).
  `group_vars/firewall` en `ansible_ssh_private_key_file` (le mot de passe
  du vault ne sert plus qu'à l'interface web). Python `/usr/local/bin/python3.11` OK.
- Le timeout venait du chemin réseau : depuis le VPN (laptop sur partage de
  connexion, `10.100.0.2`), `10.1.255.0/30` n'était pas poussé → ajout de
  `10.1.255.2/32` dans *IPv4 Local network(s)* du serveur OpenVPN.
  `ansible_host: 10.1.255.2` (adresse d'infra stable, indépendante
  d'OpenVPN) marche sur place et à distance.
- Snapshot OK : `config.xml` version 24.6, 22 règles, alias, NAT, DHCP,
  Unbound, OpenVPN.
- **Chemin de rebuild (2026-10-29)** : `--tags pfsense-backup` → snapshot +
  `config.xml` chiffré vault dans `ansible/files/pfsense/config.xml.vault`
  (versionné). Chiffrement non déterministe → réécrit seulement si le SHA-256
  de la snapshot diffère du backup déchiffré (2e lancement : « already up to
  date »). Déchiffré = snapshot (vérifié). `--tags pfsense-restore` (play
  `never` + `pfsense_restore_confirm`) : `copy` (déchiffre seul) →
  `/cf/conf/config.xml`, suppression `/tmp/config.cache`, reboot — coupe
  passerelle + VPN du rack. Install fraîche (pas de SSH) : clé USB avec
  `/config/config.xml` chargée au boot → étape du point zéro.
- **Alias + règles as code (2026-10-29)** : filtre
  `roles/pfsense/filter_plugins/pfsense_resources.py` → `host_vars/pfsense/
  pfsense_resources.yml` (4 alias, 18 règles dans l'ordre d'évaluation ; les
  2 règles associées aux redirections NAT C2 Hak5 sont exclues → avec le NAT).
  Appliqué par `pfsense_aggregate` (`order_rules: true`, aucune purge),
  `--tags pfsense-apply` (`never` + `pfsense_apply_confirm`). Seul écart au
  1er `--check` : la règle « NTP from rack to pfSense » (créée en SSH) sans
  balise `<statetype>` → pfsensible l'écrit toujours → appliqué en réel
  (accord pieric, permission Claude Code ajoutée pour l'apply) : seul ce
  changement, puis `--check` = 0, proposition snapshot = host_vars.
  pfSense a réécrit `config.xml` sans saut de ligne final → la comparaison
  du backup normalise (`awk 1`), sinon rechiffrement à chaque lancement.
- **NAT + routage as code (2026-10-29)** : 2 redirections C2 Hak5
  (`associated_rule: associated` : la règle suit la redirection) via
  l'aggregate → 0 écart du 1er coup. Passerelles `WANGW` / `l3sw`, passerelle
  par défaut `WANGW`, route `10.1.0.0/16 → l3sw` (modules `pfsense_gateway`,
  `pfsense_default_gateway`, `pfsense_route` en boucle). Seul écart : `WANGW`
  (créée par l'assistant) sans `<ipprotocol>` → appliqué en réel (micro-
  recharge du routage, sans coupure constatée), puis `--check` = 0. NAT
  sortant en `automatic` : rien à modéliser.
- **Système / DNS / DHCP as code (2026-10-29)** : `pfsense_setup` (seulement
  hostname, domaine, fuseau, NTP, DNS `dhcp-dns`, dnsallowoverride),
  `pfsense_dns_resolver` (DNSSEC, `lan`+`lo0`, 1 host + 1 domain override),
  `pfsense_dhcp_server` (opt1 seulement ; DHCP `lan` désactivé non
  modélisé). Système et DHCP à 0 du 1er coup ; Unbound : le module écrit
  toutes les options avancées par défaut (absentes du XML) → appliqué (DNS de
  pfSense redémarré, sans impact : le rack résout via `dhcp-dns`).
- **Incident de dérive (2026-10-29)** : benedict a renommé dans l'interface
  « Prometheus scrape » en « Allow Prometheus to scrape node_exporter »
  (supprimée + recréée **en fin de liste, après le `block` vers pfSense** →
  scrape :9100 en fait bloqué) entre notre `--check` et l'apply. pfsensible
  identifie par nom → a recréé « Prometheus scrape » à sa place (scrape
  rétabli), la règle de l'UI reste en doublon mort. Décision : on garde le
  nom du code, la règle de l'UI est à supprimer (bloquée par le garde-fou
  Claude Code → faite par pieric). **Garde-fou de dérive ajouté à
  `apply.yml`** : config live vs dernier backup versionné (via le filtre) →
  arrêt si différent ; testé dans les deux sens. Backup rafraîchi
  automatiquement après un apply réel. À terme : `purge_rules`.
- **Interfaces + OpenVPN + CA/certs/users as code (2026-10-29)** : toute la
  config de pfSense est modélisée. Secrets (clés et certificats de la CA et
  des 4 certificats, hash bcrypt des 4 utilisateurs, clé TLS OpenVPN) dans
  `host_vars/pfsense/vault.yml` (`vault_pfsense_secrets`), références dans
  `pfsense_resources.yml` ; la snapshot écrit les deux propositions. Hors
  code : certificat autosigné de l'UI (pas de CA), lien user↔cert (option
  absente du module), SNMP/syslog/cron/paquets (backup). `--check` : 0 sur
  tout sauf **LAN** (balises vides `gateway`/`ipaddrv6`/`subnetv6`/
  `gatewayv6` à retirer) et **OpenVPN** (`ncp_enable` explicite,
  `remote_cert_tls` vide retiré, clé TLS CRLF → LF) : sans effet mais
  reconfigure `igc1` (transit) et redémarre OpenVPN → **appliqué sur place
  le 2026-10-29** (laptop sur MGMT `10.1.240.108`, SSH tenu), puis `--check`
  = **0 sur toute la config**, proposition = host_vars, secrets = vault.
- ⚠️ **Fuite de la clé TLS OpenVPN (2026-10-29)** : `pfsense_openvpn_server`
  l'affiche dans ses messages d'erreur (clé en CRLF refusée) → apparue dans
  la session Claude et dans `ansible.log` (nettoyé). `no_log` ajouté sur les
  tâches à secrets (`pfsense_hide_secrets`). **Régénérer la clé TLS**
  recommandé (tls-auth : protège l'accès au serveur, ne déchiffre pas le
  trafic) puis redistribuer les configs clientes, backup, régénérer le vault.

## Où on en est / prochaine étape

- [x] Décisions d'archi tranchées (ci-dessus).
- [x] Dossier `~/Documents/cloud-1-iac` créé + ce `context.md` (dans `docs/`).
- [x] `git init` + `.gitignore` (généré gitignore.io : terraform, ansible,
      packer, macos ; règles projet ajoutées au fur et à mesure — secrets en
      priorité). `.terraform.lock.hcl` volontairement versionné.
- [x] Dossier `ansible/` repris d'`infra04` (inventaire, rôles, cfg, site.yml).
- [x] Restructuration vers le layout ci-dessus (`00-network/` et `30-config/`
      supprimés, `ansible.log` gitignoré,
      `group_vars/all/vars.yml`, `site.yml` → imports, `requirements.yml`).
      `--syntax-check site.yml` et `ansible-inventory --graph` OK.
- [x] Inventaire refait (zones/, baremetal, backup) — `ansible-inventory
      --graph` sans warning.
- [x] 1er commit (amend à venir pour inclure l'inventaire).
- [x] Accès iLO : `host_vars` pve01/pve02, vault de groupe, fichier de mot de
      passe du vault.
- [x] `10-bootstrap.yml` **lecture seule** (`redfish_info` Systems/Manager +
      `uri` GET brut VirtualMedia/2 et Systems/1) — OK sur pve01 et pve02.
- [x] Clé SSH dans `key/` (gitignoré) ; `private_key_file` déplacé du cfg vers
      les groupes Linux.
- [x] **Couche 10, étape 2** : ISO servi par `npx http-server` (laptop
      `10.1.240.111`, même sous-réseau mgmt que les iLO → pas de routage),
      Range vérifié (206). `iso_url` dans `group_vars/baremetal/vars.yml`.
      Bloc montage/éjection dans `10-bootstrap.yml`, tag `never, media-test`
      (jamais exécuté par défaut), éjection en `always`, assert
      `BootOnNextServerReset` false. **Testé OK sur pve02** (monté + éjecté,
      aucun impact). Constat : l'iLO 4 fait un `GET <iso>` au montage et un
      `GET <iso>?EJECT` à l'éjection (User-Agent vide).
- [x] Couche 10, étape 3 (partiel) : méthode de boot tranchée (HPE),
      template `answer.toml.j2` + variables par hôte, mot de passe root haché
      au rendu (passlib installé), rendu validé.
- [x] Couche 10, étape 3 : hook first-boot réseau, build ISO par hôte
      (`--tags build-iso`), answer validé par l'outil officiel, 2 ISO construits.
- [x] Couche 10, étape 4 : play d'install destructif écrit (`never, install` +
      confirmation). **Non exécuté** — test en fin de lab.
- [ ] Gitea en LXC + push-mirror GitHub.
- [ ] Synology dans le périmètre (partage ISO + iSCSI) — exploration API.
- [x] Couche 00, étape 1 : snapshots lecture seule l2sw + l3sw, YAML des
      ressources (l2sw gathered, l3sw parsed hors ligne), VTP transparent.
- [ ] Couche 00, suite : pfSense (SSH), host_vars des switchs + `--check
      --diff` à zéro, `no vstack`, durcissement, Oxidized (plus tard).
- [ ] Couches 20 → 30, puis Makefile.

### Couche 20 — Terraform (squelette, 2026-10-29)
`20-proxmox/` : provider `bpg/proxmox` **~> 0.119** (validé : 0.119.0,
`.terraform.lock.hcl` versionné), Terraform >= 1.5, état local gitignoré,
`terraform.tfvars` gitignoré (`.example` versionné), **lecture seule** :
`data "proxmox_virtual_environment_vms"` + output. Pas de ressource écrite à
la main : les VMs existent, le 1er plan voudrait les remplacer. Étape 2 :
blocs `import` (`imports.tf`, fait le 2026-11-04) + `terraform plan
-generate-config-out` → code généré depuis les VMs réelles (0 écart, comme
`gathered`). Terraform non installé localement → image
`hashicorp/terraform:1.9.8` (`make vms-init` / `make vms-plan`). Token API
`terraform@pve!iac` à créer (Datacenter > Permissions > API Tokens).

### Existant du repo piscine (relevé 2026-10-30)
Tout ce qui servira aux couches suivantes est consolidé dans
**`docs/existant-piscine.md`** : cluster (HA, règles d'affinité, modèle CPU
Haswell pour la migration), stockage (iSCSI, masking, multipath, NFS ISO),
inventaire des guests avec VMID/stockage/nœud/HA (pour Terraform), templates
Packer, supervision infra06 (6 rôles), k3s infra05, et la **copie hors site
des backups (PBS distant, sync push chiffré : clé de chiffrement
indispensable pour restaurer)**. Le pbs est sur `local-lvm` de pve02
**volontairement** (survit à une panne du NAS). Couche 30 : README réels des
4 rôles d'infra04, chemins `group_vars/all/vars.yml` corrigés,
`make config-check`.

### Qualité — ansible-lint (2026-10-29)
`ansible-lint` 26.10 (pipx, environnement séparé ; collections du venv
Ansible via `ANSIBLE_COLLECTIONS_PATH`) : 268 remarques → **0, profil
`production`**. Corrigé : `changed_when` sur les commandes qui modifient,
noms de tâches/plays, `---`, métadonnées génériques des rôles d'infra04,
`# SPDX`, tests galaxy. `# noqa: args[module]` sur les tâches pfSense en
`"{{ item }}"` (lint ne lit pas les paramètres templatés ; validés en réel
par les `--check`). Écartés **avec justification** dans `.ansible-lint` :
`var-naming[no-role-prefix]` (variables par domaine partagées inventaire /
rôles), `role-name` (rôles à tiret d'infra04). `.yamllint` : séquences
indentées ou non (fichiers générés), vaults ignorés (chiffrés). `make lint`.

### ⚠️ Avant le test de réinstallation (lu le 2026-10-29)
- **La VM `pbs` (2400) et son datastore sont sur le `local-lvm` de pve02**
  (disques `vm-2400-disk-0/1`), donc sur le RAID que l'install efface.
  **Décision pieric (2026-10-29) : acceptable**, les backups ont une copie
  distante. Conséquence : après une réinstallation de pve02, la VM `pbs`
  doit être recréée (couche 20) ou restaurée depuis la copie distante ;
  d'ici là, le job de backup vers `pbs-store1` échoue. Si possible le
  garder (« tant mieux ») : **garde-fou ajouté à `install.yml`** qui liste
  (SSH, lecture seule) les volumes de guests sur le `local-lvm` du nœud et
  s'arrête s'il y en a, sauf `-e pve_install_allow_local_guests=true` ;
  avant l'install : `qm migrate 2400 pve01 --with-local-disks` (non testé
  en réel : commande root bloquée en remote).
- Après une réinstallation, le nœud doit **retrouver son IQN iSCSI** (le
  masking du NAS refuse tout autre initiateur) et **rejoindre le cluster**
  (`INFRA-CLUSTER`, qdevice `qdevice03` `10.1.240.13`) : rôle `pve_config`
  (validé en --check le 2026-10-30) + procédure manuelle de re-join dans `tasks/cluster.yml`.

### Reprise suggérée pour la nouvelle session
0. **Pause du 2026-10-28 soir — où on s'est arrêté :**
   - l2sw : `--tags apply --check` = **zéro changement** (commité). Valeurs par
     défaut IOS rendues explicites sur les SVI (`redirects`, `unreachables`,
     IPv6 = true) : avec `replaced`, `ios_l3_interfaces` envoie sinon
     `no ip redirects` (code `handle_defaults` du module).
   - l3sw (mode `rendered`) : **zéro changement au `--check` (2026-10-29)**.
     Le timeout venait du candidat écrit avec des `\n` littéraux (une seule
     ligne) → construction déplacée dans `roles/ios_switch/templates/ios_candidate.j2`
     (liste de lignes), écrite dans `build/network/l3sw/candidate.cfg`
     (`src` d'`ios_config` attend un chemin). Normalisation à l'affichage
     IOS 12.2 : `no shutdown` retiré, `deny` + 3 espaces, pas de `host` en
     ACL standard. Test sans toucher au switch : `-e ansible_host=127.0.0.1`
     puis diff hors ligne `NetworkConfig` (moteur d'`ios_config`) contre la
     running-config sauvegardée. Limite : `ios_config` voit ce qui
     *manque*, pas ce qui est *en trop* sur le switch.
   - Historique réécrit (messages détaillés, sans attribution) ; ancienne
     version dans la branche `backup-before-reword` (à supprimer).
   - Serveur `npx` arrêté.
   - 2026-10-29 : couches 00 et 10 refactorées en rôles (`redfish_bootstrap`,
     `ios_switch`, `pfsense`), validées en local puis en lecture seule sur
     la prod (voir « Playbooks = aiguillages »). Le probe iLO de pve02 a
     renvoyé 401 (`NoValidSession`) : le mot de passe d'`admin_yuumi` dans
     le vault ne correspondait plus à l'iLO ; `vault.yml` (baremetal) mis à
     jour par pieric, probe OK ensuite.
   - **Rôle `pve_config`** (validé en `--check --diff` sur la prod le 2026-10-30, CHAP dans `group_vars/pve/vault.yml`) écrit d'après la doc
     du module 03 : dépôts, /etc/hosts, NTP, IQN iSCSI enregistré, CHAP,
     multipath, stockages cluster ; tag `never, pve-config` dans
     `10-bootstrap.yml`. À valider après le relevé réel des nœuds (bloqué
     en remote : commande root sur les hyperviseurs → à lancer par pieric).
     Secret CHAP à mettre dans un vault.
   - À faire ensuite : pfSense (SSH bloqué, sshguard ?), relevé des pve
     (`no vstack` explicite, vty `access-class`, `no ip http server`).
1. Lire ce `context.md`.
2. Couche 10 écrite de bout en bout ; seul reste le **test réel de l'install
   en fin de lab** : vider un nœud, prévenir le groupe, servir
   `10-bootstrap/build/` en npx, `--tags install --limit pveXX -e
   pve_install_confirm=true`. Points à observer : hook réseau appliqué,
   cluster/iSCSI à refaire après (couche suivante).
- **Makefile (2026-10-29)** : une cible par étape dans l'ordre du rebuild
  (`make help`) ; cibles qui modifient → `CONFIRM=yes` (+ `HOST=` par nœud),
  en plus des confirmations des playbooks. Vérifié en simulation (`make -n`)
  et garde-fous, rien lancé.
3. Couche 00 : intégrer le parsing hors ligne du l3sw au repo (aujourd'hui
   dans un playbook temporaire), YAML → `host_vars/l2sw.yml` / `l3sw.yml`
   (VLAN gérés sur les **deux** switchs depuis le passage en transparent),
   `--check --diff` = zéro changement ; débloquer SSH pfSense ;
   `show vstack config` / `no vstack`.
4. Preflight fait (`ansible-playbook preflight.yml`) : chaque zone dans un
   block/rescue (un échec est enregistré, pas fatal : sinon un play dont tous
   les hôtes échouent arrête le playbook), verdict final. 1er lancement :
   tout OK sauf **pfSense SSH fermé** (port 22 fermé sur toutes ses adresses,
   443 ouvert → pas sshguard ; à vérifier dans l'UI : SSH activé ? sshd ?).
6. Passage en rôle `redfish_bootstrap` (nommé par ce qu'il fait) une fois les
   étapes connues : un fichier de tâches par étape, partie iLO 4 isolée
   (comme `Debian.yml` / `Alpine.yml`), `assert` de confirmation (défaut
   faux) avant le destructif.
7. Ordre de rebuild : le pbs (VM) doit remonter tôt (restauration des autres
   VMs) → Makefile / couche 20.

# context.md — cloud-1-iac

> Doc de passation, lu en premier par une nouvelle session dans ce repo.
> Mis à jour le 2026-11-04 : état réel de toutes les couches, sources de
> vérité, pièges appris. Les constats techniques des couches 10 et 00 (iLO 4,
> IOS 12.2, pfSense) sont gardés tels quels plus bas.

## Le but

**GitOps bare-metal** du rack de la Piscine Infrastructure (42 Lausanne,
groupe de 3-4) : ce repo est la *source de vérité* de toute l'infra et doit
permettre de **tout remonter**, du métal aux applications, puis de restaurer
les backups. Extension perso au-delà des modules notés, partagée au groupe.

- Ordre de rebuild : point zéro manuel (`docs/runbook-point-zero.md`) →
  réseau → NAS → Proxmox → cluster → `pve_config` → PBS → restauration des
  guests (depuis `pbs-offsite`) → Terraform (HA) → config → applications k8s.
  Le Makefile porte l'ordre (`make help`), `make preflight` vérifie le point
  zéro.
- Pannes partielles (un nœud, le PBS seul, le poste de contrôle) : section 9
  du runbook.

## Le mode de travail (IMPORTANT)

- Claude = **copilote** : il propose (direction, choix à défendre), écrit le
  code et lance ce qui est local ou en lecture seule ; pieric décide.
- **Jamais d'écriture sur la prod sans feu vert explicite** (« go »), même
  quand un plan ou un `--check` a l'air propre. Lecture seule (`--check`,
  `show`, `pvesh get`, relevés) : permis. Toujours `--check --diff` d'abord,
  et lire chaque écart avant d'appliquer.
- **La prod fait foi** : quand le code et la prod divergent, on comprend
  d'abord (souvent une modif à la main de l'équipe), on aligne le code sur la
  prod, on n'écrase pas.
- **Commits sans attribution** (pas de Co-Authored-By), messages en anglais,
  sujet + liste. Pousser sur `origin` (Gitea), le miroir suit vers GitHub.
- Secrets : lab, une fuite n'est pas grave, mais ils vont **toujours** dans
  un vault, récupérés sans affichage. Ne jamais lire un secret avec
  `ansible -m debug` : `ansible.log` l'enregistre (arrivé deux fois, nettoyé).
- `ansible_host` = noms d'hôtes (préférence de pieric), sauf dhcp-dns (IP :
  c'est le DNS).

## Architecture : couches et outils

| Couche | Quoi | Outil | État (2026-11-04) |
|---|---|---|---|
| 00 réseau | switchs l3sw (3560-V2, IOS 12.2) / l2sw (2960-X), pfSense | Ansible `cisco.ios`, `pfsensible.core` | ✅ `--check` = 0 (VLAN 13 de l'équipe repris) |
| 05 stockage | Synology RS812RP+ (DSM 6.2) : LUN, cible iSCSI, masking, NFS | Ansible, API web DSM (`uri`) | ✅ audit 16/16 ; création iSCSI testée ; partage NFS manuel |
| 10 bootstrap | install Proxmox par l'iLO (Redfish + ISO auto-install) | Ansible `redfish_bootstrap` | ✅ écrit ; **test réel sur place à faire** |
| 10 nœuds | dépôts, iSCSI, datacenter, stockages, backup, comptes API | Ansible `pve_config` | ✅ `--check` = 0 ; join du cluster manuel |
| 10 PBS | datastore, accès, jobs, sync chiffré hors site | Ansible `pbs_config` | ✅ `--check` = 0 |
| 15 templates | Debian / Ubuntu / Alpine | Packer (`proxmox-iso`) | ✅ 8005 reconstruit et testé (racine qui s'agrandit) |
| 20 guests | VMs, LXC, HA (règles PVE 9) | Terraform `bpg/proxmox`, état sur HCP | ✅ `No changes` ; HA possède le placement |
| 30 config | base (common, users, hardening), DNS/DHCP, rproxy, supervision, Gitea, k3s | Ansible | ✅ 12/15 à 0 ; k3s : script figé + paquets en attente |
| 40 k8s | nginx, ingress, network policies, Postgres | kustomize via `k8s_apps` | ✅ `kubectl diff` = 0 |

## Layout du repo

```
cloud-1-iac/
├── Makefile                    # une cible par étape, CONFIRM=yes pour écrire
├── network/addressing.yml      # SOURCE UNIQUE de l'adressage (DHCP, DNS, IP des guests, amonts rproxy)
├── ansible/
│   ├── 00-network.yml 05-storage.yml 10-bootstrap.yml 30-config.yml 40-k8s.yml preflight.yml site.yml
│   ├── inventory/              # zones/ (où, ansible_host) + baremetal/vms/lxc/network/storage (quoi)
│   │   ├── group_vars/<groupe>/{vars,vault}.yml
│   │   └── host_vars/          # pveXX (iLO, install), l2sw/l3sw (ios_resources.yml)
│   ├── roles/                  # un rôle par sujet, README réel chacun
│   └── files/                  # backup pfSense chiffré, tableaux de bord Grafana
├── 10-bootstrap/               # Dockerfile de l'ISO auto-install (iso/, build/ gitignorés)
├── 15-templates/               # Packer (variables : make templates-vars)
├── 20-proxmox/                 # Terraform (un fichier par guest, ha.tf, locals.tf)
├── 40-k8s/                     # manifests + kustomization (Secret Postgres généré)
├── docs/                       # ce fichier, runbook, existant-piscine
├── build/ key/                 # gitignorés : relevés réseau, clé d'automatisation
└── .ansible-lint .yamllint     # make lint : profil production
```

Rôles : couche 00 `ios_switch`, `pfsense` ; 05 `synology_storage` ; 10
`redfish_bootstrap`, `pve_config`, `pbs_config` ; 30 `common`, `users`,
`ssh-hardening`, `cis-hardening` (infra04), `dnsmasq`, `lxc_access`,
`rproxy`, `gitea`, `node-exporter`, `prometheus`, `alertmanager`,
`pve-exporter`, `snmp-exporter`, `snmptrapd`, `grafana` (infra06),
`k3s-control`, `k3s-worker` (infra05) ; 40 `k8s_apps` ; outils `preflight`.

## Sources de vérité

- **Adressage** : `network/addressing.yml` (réseaux, réservations, une ligne
  par machine, services derrière rproxy). Ajouter une VM = une ligne + son
  `vm_*.tf`, puis `make vms-apply` et `make dns-apply` (`network/README.md`).
- **Personnes** : `users_admins` (`group_vars/all/vars.yml`) → comptes admin
  des VMs, clés `root` des LXC (`lxc_access`), clés du compte Gitea.
- **Repo** : Gitea (`ssh://git@gitea01.cloud-1.fun:2222/gitea-admin/cloud-1.fun.git`,
  compte `gitea-admin`) → push mirror vers `github.com/pieric-ux/cloud-1.fun`
  à chaque push. En rebuild total : cloner GitHub.
- **État Terraform** : HCP Terraform, organisation `cloud-1-fun`, workspace
  `cloud-1-proxmox`, exécution locale (jeton utilisateur dans
  `~/.terraform.d/credentials.tfrc.json`).
- **Secrets** : vaults Ansible (mot de passe `~/.ansible/.vault_pass_cloud1`,
  `600`, aussi dans Bitwarden). Clé de chiffrement des backups hors site :
  dans le vault `pve` **et** Vaultwarden.

| Vault (`group_vars/…/vault.yml`) | Contenu |
|---|---|
| `baremetal` | iLO, mots de passe root des nœuds |
| `switches`, `firewall`, `host_vars/pfsense` | switchs, pfSense, OpenVPN ; backup pfSense chiffré : `ansible/files/pfsense/config.xml.vault` |
| `pve` | CHAP iSCSI, jetons PBS, clé hors site, jetons Terraform et Packer (secret seul) |
| `backup` | `token.shadow` PBS, mot de passe du remote, clé `offsite-key` |
| `storage` | compte DSM |
| `monitoring` | jeton pve-exporter, communauté SNMP |
| `k3s` | jeton du cluster, mot de passe Postgres |
| `rproxy` | identifiants Infomaniak (certbot DNS-01) |
| `git` | secrets Gitea, mot de passe `gitea-admin`, jeton GitHub (miroir) |

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

## Pièges appris (à connaître avant de toucher au code)

- **Terraform / bpg** : un guest déplacé par la HA ferait *remplacer* la VM
  (nouveau nœud = nouvelle VM pour le provider) → `ignore_changes =
  [node_name]` sur les 10 guests HA. Sur un clone sans bloc `cpu`, le provider
  met `qemu64` → CPU toujours explicite (`Haswell-noTSX-IBRS` + flags).
  `replicate` par défaut à `true` ≠ Proxmox. Les VMs importées n'ont pas de
  bloc `clone` : un `apply` qui *crée* une VM restaurable la créerait vide.
- **Proxmox** : un commentaire d'utilisateur est coupé à la virgule. Les
  règles HA PVE 9 refusent deux modifications simultanées (réessayer). En
  PVE 9, `VM.Monitor` n'existe plus (`VM.GuestAgent.*`).
- **DSM 6.2** : les API `entry.cgi` décodent chaque paramètre en JSON (envoyer
  `"2"` pour une chaîne). `Share.create` refuse `shareinfo` en clair (chiffré
  par le navigateur) → partage NFS manuel. La suppression d'une LUN est
  asynchrone. Le WWID multipath ne se déduit pas de l'uuid de la LUN.
- **Switchs** : l3sw en mode `rendered` (`ios_config`) ne voit que ce qui
  *manque*, pas ce qui est en trop ; l2sw en ressources (`replaced`).
- **Template Debian** : l'ancienne recette `atomic` mettait la swap après la
  racine (pas d'agrandissement par cloud-init) → corrigé dans le preseed,
  8005 reconstruit ; le 8002 de l'équipe a encore l'ancien partitionnement.
- **Prometheus / SNMP** : la prod avait des ajouts à la main (jobs et modules
  STP, auth `rack_v2_vlan240` = communauté + `@240`) → repris dans les rôles.
- **k3s** : `get.k3s.io` change en amont → script figé sur la release.
- **vault-01** : conteneur applicatif (image OCI Vaultwarden, Alpine sans
  SSH ni Python) → hors Ansible, revient par restauration de `/data`.
- **Poste de contrôle** : sur le VLAN MGMT sans VPN, OrbStack a besoin de la
  permission macOS *Réseau local*. zsh ne découpe pas `$VAR` en mots (passer
  par une fonction). Un `git add` avec un chemin absent échoue en entier.
- **Ansible 2.21** : pas de conversion fiable texte → dict après une boucle
  Jinja (filtres purs), `vars` n'est plus fiable (utiliser `query('varnames')`),
  échappements `\1` fragiles dans les blocs YAML repliés (préférer `split`,
  `splitext`, `dict2items(key_name=...)`).

## Ce qui reste manuel ou hors du code

- Point zéro (console des switchs, pfSense, DSM, iLO, RAID, ISO), création du
  cluster + join + qdevice, installation de la VM PBS, partage NFS du NAS,
  restaurations (runbook).
- Hors code : le PBS distant (Infomaniak), le qdevice03 (seul node-exporter),
  vault-01, les VMs de test (captive-portal, sorti de Terraform et du DNS ;
  son port l2sw Gi1/0/39 `MR600-CAPTIVE` est gardé actif tant que le test
  dure), le template 8002 de l'équipe.
- Limites acceptées pour le lab : Postgres sur `local-path` (k3s-worker-1),
  Alertmanager sans notifications, tableaux de bord Grafana importés à la
  main, compte DSM `admin`.

## Prochaines étapes possibles

1. **CI sur Gitea** (runner dans le rack) : lint + `--check` de chaque couche
   à chaque push / chaque nuit — la vérification globale du 2026-11-04 a
   trouvé une dérive à la main sur les switchs (VLAN 13) qu'un `apply` aurait
   défaite.
2. **VPN** : domaine de recherche `cloud-1.fun` poussé, un certificat par
   appareil, rotation de la clé TLS OpenVPN (fuitée dans un log au début).
3. Test réel de l'installation par l'iLO (sur place, groupe prévenu).
4. Compte DSM dédié, PBS distant dans le code.

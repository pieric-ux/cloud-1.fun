# Runbook — point zéro

Procédure manuelle pour remettre le rack dans un état où **le repo peut tout
reconstruire**. Tout ce qui est ici est manuel parce qu'aucune API n'existe
encore à ce stade (pas d'IP, pas d'OS, pas de SSH), ou parce que le matériel ne
le permet pas. Le reste est automatisé.

**Quand l'utiliser** : rebuild complet, remplacement d'un équipement (switch,
pfSense, disques, contrôleur RAID), nouveau poste de contrôle.

**Règle** : suivre les étapes dans l'ordre et ne passer à la suivante qu'une
fois la vérification OK. Chaque étape dit *quoi*, *pourquoi c'est manuel*,
*comment vérifier*.

| # | Étape | Si déjà en place |
|---|---|---|
| 1 | Poste de contrôle | toujours vérifier |
| 2 | Switchs (accès de base) | sauter si les switchs répondent en SSH |
| 3 | pfSense (restauration de la config) | sauter si pfSense répond en SSH |
| 4 | Synology (DSM) | sauter si DSM répond |
| 5 | iLO (IP + compte) | sauter si le probe iLO passe |
| 6 | RAID P440 | sauter si la vérification RAID du probe passe |
| 7 | ISO Proxmox | sauter si les ISO préparés existent |
| 8 | Enchaînement automatisé | — |

---

## 1. Poste de contrôle

**Pourquoi manuel** : c'est la machine qui lance tout le reste.

1. Cloner le repo depuis GitHub (Gitea n'existe pas encore pendant un rebuild).
2. Ansible et ses dépendances :
   ```bash
   pipx install --include-deps ansible
   pipx inject ansible passlib ansible-pylibssh 'paramiko<4'
   cd ansible && ansible-galaxy collection install -r requirements.yml
   ```
   `paramiko<4` : les IOS 12.2 / 15.2 n'offrent que du kex SHA-1.
3. Secrets depuis Bitwarden :
   - mot de passe du vault → `~/.ansible/.vault_pass_cloud1`, droits `600` ;
   - clé SSH automation → `key/ansible` (`600`) et `key/ansible.pub`.
4. Docker (OrbStack) démarré, Node.js / npx installé.
5. Être sur le VLAN MGMT (`10.1.240.0/24`), ou sur le VPN une fois pfSense
   restauré.

**Vérification**
```bash
cd ansible
ansible-vault view inventory/group_vars/baremetal/vault.yml >/dev/null && echo vault OK
ansible-inventory --graph
```

---

## 2. Switchs — accès de base

**Pourquoi manuel** : un switch neuf ou effacé n'a ni IP ni SSH. On ne
configure que le minimum pour qu'Ansible se connecte ; tout le reste vient du
code (`00-network`).

Par la console série (9600 8N1), sur le **l3sw** (3560-V2) :
```
enable
configure terminal
hostname l3sw
ip domain-name cloud-1.fun
username admin privilege 15 secret <mot de passe : vault_switch_admin_password_l3sw>
crypto key generate rsa modulus 2048
ip ssh version 2
vlan 240
 name MGMT
interface Vlan240
 ip address 10.1.240.1 255.255.255.0
 no shutdown
line vty 0 15
 login local
 transport input ssh
end
write memory
```
Sur le **l2sw** (2960-X), même chose avec `hostname l2sw`, l'IP
`10.1.240.2 255.255.255.0` sur `Vlan240`, `ip default-gateway 10.1.240.1`, et
l'uplink vers le l3sw en trunk (Po1 = Gi1/0/1-12, VLAN 240 autorisé).
Brancher le poste de contrôle sur un port en accès VLAN 240.

**Vérification**
```bash
ssh admin@10.1.240.1   # puis 10.1.240.2
cd ansible && ansible-playbook 00-network.yml --limit switches   # snapshot lecture seule
```
Ensuite : `ansible-playbook 00-network.yml --tags apply --check --diff --limit switches`
montre tout ce qui manque ; appliquer avec `-e network_apply_confirm=true`.

---

## 3. pfSense — restauration de la config

**Pourquoi manuel** : une installation fraîche n'a ni SSH ni la clé
automation ; c'est la config restaurée qui les ramène.

1. Installer pfSense CE 2.7.2 sur le mini PC (ports : `igc0` WAN, `igc1` LAN /
   transit vers le l3sw Fa0/48, `igc2` ADMINCONSOLE).
2. Préparer une clé USB (FAT32) avec la config versionnée, déchiffrée :
   ```bash
   mkdir -p /Volumes/<USB>/config
   cd ansible && ansible-vault decrypt --output /Volumes/<USB>/config/config.xml files/pfsense/config.xml.vault
   ```
3. Brancher la clé et démarrer pfSense : il charge `/config/config.xml` au
   démarrage quand il n'a pas encore de config.
4. **Effacer le `config.xml` de la clé** (il contient clés et hashes en clair).

**Vérification**
```bash
ssh -i key/ansible admin@10.1.255.2 'echo OK'
cd ansible && ansible-playbook 00-network.yml --limit pfsense --tags pfsense-apply --check --diff
```
Si le backup est plus ancien que le code, l'apply rattrape l'écart.

---

## 4. Synology — DSM

**Pourquoi manuel** : pas d'API avant l'installation de DSM.

1. Installer DSM avec Synology Assistant, créer le premier compte admin.
2. Réseau : LAN1 `10.1.20.21`, LAN2 `10.1.20.22` (VLAN 20 STORAGE).
3. iSCSI (LUN, cible, CHAP) : à reprendre de la doc du module 03 du repo
   piscine (`infra03/docs/module03/iscsi_setup.md`) en attendant la couche
   `05-storage`.
4. Partage HTTP des ISO : à prévoir avec `05-storage` ; en attendant, le poste
   de contrôle sert les ISO (étape 7).

**Vérification** : interface DSM joignable, LUN visible.

---

## 5. iLO — IP et compte

**Pourquoi manuel** : réglés dans l'iLO lui-même, avant tout OS. Ils survivent
à une réinstallation : à refaire seulement si la carte mère ou l'iLO est
remplacé ou réinitialisé.

| Serveur | IP iLO | Compte (`host_vars`) |
|---|---|---|
| pve01 | `10.1.240.21` | `admin_teemo` |
| pve02 | `10.1.240.22` | `admin_yuumi` |

Au démarrage (F8 / iLO RBSU) ou depuis l'interface iLO avec le compte
`Administrator` d'usine (étiquette du serveur) : IP fixe, masque
`255.255.255.0`, passerelle `10.1.240.1` ; créer le compte avec les droits
Login, Virtual Media, Virtual Power and Reset. Mot de passe : celui du vault
(`vault_ilo_password_pve01` / `_pve02`).

**Vérification**
```bash
cd ansible && ansible-playbook 10-bootstrap.yml   # probe lecture seule, les 2 serveurs
```

---

## 6. RAID P440 — seulement si disques ou contrôleur remplacés

**Pourquoi manuel** : sur Gen9 / iLO 4, l'API SmartStorage est en lecture
seule ; un array ne se crée qu'avec `ssacli` ou HPE SSA. La config RAID vit sur
le contrôleur et les disques : elle survit aux réinstallations.

RAID attendu (`pve_raid` dans les `host_vars`) : RAID 1, stripe 256 Kio.

| Serveur | Contrôleur | Commande |
|---|---|---|
| pve01 | P440, slot 1 | `ssacli ctrl slot=1 create type=ld drives=1I:1:17,1I:1:18 raid=1 ss=256` |
| pve02 | P440ar intégré, slot 0 | `ssacli ctrl slot=0 create type=ld drives=1I:3:1,1I:3:2 raid=1 ss=256` |

Sans OS : HPE Smart Storage Administrator au démarrage (F10, Intelligent
Provisioning), mêmes paramètres.

**Ensuite, obligatoire** : un volume recréé a un **nouvel identifiant**. Le
lire (probe, ou `VolumeUniqueIdentifier` dans l'iLO) et mettre à jour
`pve_install_disk_serial` dans `host_vars/pveXX.yml` (`3` + identifiant en
minuscules), puis reconstruire l'ISO (étape 7).

**Vérification** : le probe affiche `RAID 1 OK on Smart Array … = install
target`. Sinon, l'installation refusera de démarrer.

---

## 7. ISO Proxmox

**Pourquoi manuel** : téléchargement et service local des fichiers.

1. Télécharger l'ISO Proxmox VE 9.2 depuis proxmox.com dans
   `10-bootstrap/iso/`, vérifier son SHA-256 avec celui publié.
2. Construire un ISO auto-install par hôte (local, Docker) :
   ```bash
   cd ansible && ansible-playbook 10-bootstrap.yml --tags build-iso
   ```
3. Pendant une installation seulement, servir les ISO préparés (requêtes
   Range obligatoires) :
   ```bash
   cd 10-bootstrap/build && npx http-server -p 8080 -a 0.0.0.0
   ```
   `pve_install_iso_url` pointe sur l'IP du poste de contrôle : l'adapter si
   elle a changé.

**Vérification**
```bash
curl -s -o /dev/null -w '%{http_code}\n' -r 0-1023 http://<ip-poste>:8080/pve01/pve-auto-pve01.iso   # 206
```

---

## 8. Enchaînement automatisé

Une fois le point zéro fait, dans l'ordre (depuis `ansible/`) :

1. **Réseau** : `ansible-playbook 00-network.yml --tags apply,pfsense-apply --check --diff`,
   puis sans `--check` avec `-e network_apply_confirm=true -e pfsense_apply_confirm=true`.
2. **Stockage** (`05-storage`, à venir) : partage des ISO, iSCSI.
3. **Bare metal**, un nœud à la fois, groupe prévenu. **Vider le nœud
   d'abord** : les guests dont les disques sont sur son `local-lvm` sont
   effacés avec lui (ex. la VM `pbs` sur pve02) →
   `qm migrate <vmid> <autre nœud> --with-local-disks`, ou déplacer leurs
   disques sur `synology-lvm`. L'installation s'arrête s'il en reste
   (`-e pve_install_allow_local_guests=true` pour accepter leur perte).
   `ansible-playbook 10-bootstrap.yml --tags install --limit pve02 -e pve_install_confirm=true`.
4. **Configuration des Proxmox** (cluster, iSCSI `synology-lvm`) : à venir.
5. **VMs** (`20-proxmox`, Terraform : squelette en lecture seule, import du
   code depuis les VMs réelles à venir) puis **config** (`30-config.yml`).
6. **Restauration des backups** (PBS : pve02 + copie hors site). Après un
   crash total, le PBS du rack est perdu : restaurer depuis le PBS distant
   `pbs-offsite`, ce qui demande **la clé de chiffrement du sync job** et
   l'accès au serveur (gestionnaire de mots de passe de l'équipe ; détails
   dans `docs/existant-piscine.md`).

**Avant l'enchaînement**, vérifier automatiquement les étapes 1 à 7 (lecture
seule, ne modifie rien) :
```bash
cd ansible && ansible-playbook preflight.yml
```
Toutes les vérifications tournent même si l'une échoue ; le dernier play donne
le verdict (`Point zero ready` ou la liste des problèmes par hôte). Les
avertissements (Docker, npx, ISO préparés, droits du fichier de mot de passe
du vault) ne bloquent pas.

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
| 8 | Enchaînement automatisé (rebuild complet) | — |
| 9 | Pannes partielles (un nœud, le PBS seul) | — |

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
4. Docker (OrbStack) démarré, Node.js / npx installé, Packer
   (`brew install packer`) pour les templates. Terraform tourne dans Docker
   (`make vms-*`), pas d'installation locale.
5. Être sur le VLAN MGMT (`10.1.240.0/24`), ou sur le VPN une fois pfSense
   restauré. Sur le VLAN MGMT sans VPN, OrbStack a besoin de la permission
   macOS **Réseau local** (Réglages Système > Confidentialité et sécurité),
   sinon les conteneurs ne joignent pas les nœuds.
6. HCP Terraform (état de la couche 20, organisation `cloud-1-fun`) : un
   compte invité dans l'organisation et un jeton **utilisateur** (Account
   settings > Tokens ; un jeton d'organisation ne peut pas lancer de plan) :
   ```bash
   docker run --rm -it -v $HOME/.terraform.d:/root/.terraform.d hashicorp/terraform:1.9.8 login
   ```
   L'état est chez HCP : il survit à la perte du rack et du poste.

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

## 8. Enchaînement automatisé (rebuild complet)

Une fois le point zéro fait, dans l'ordre, depuis la racine du repo. Chaque
étape a sa cible `*-check` (lecture seule) avant la cible qui écrit
(`CONFIRM=yes`) : toujours lire l'aperçu d'abord.

**Avant l'enchaînement**, vérifier automatiquement les étapes 1 à 7 (lecture
seule, ne modifie rien) :
```bash
make preflight
```
Toutes les vérifications tournent même si l'une échoue ; le dernier play donne
le verdict (`Point zero ready` ou la liste des problèmes par hôte). Les
avertissements (Docker, npx, ISO préparés, droits du fichier de mot de passe
du vault) ne bloquent pas.

### 8.1 Réseau

```bash
make network-check
make network-apply CONFIRM=yes
```

### 8.2 Stockage (NAS)

Manuel tant que la couche `05-storage` n'existe pas : LUN iSCSI, cible,
masking par IQN, CHAP (étape 4). Le secret CHAP est dans
`group_vars/pve/vault.yml`.

### 8.3 Proxmox sur les deux nœuds

Un nœud à la fois, groupe prévenu. Sur un rack encore en service, **vider le
nœud d'abord** (les guests sur son `local-lvm` sont effacés avec lui, ex. la
VM `pbs` sur pve02 ; l'installation s'arrête s'il en reste).
```bash
make bootstrap                        # probe iLO + RAID
make iso && make serve-iso            # serve-iso dans un second terminal
make install HOST=pve01 CONFIRM=yes
make install HOST=pve02 CONFIRM=yes
```

### 8.4 Cluster et qdevice (manuel)

Pas automatisé exprès : un join raté casse le cluster.
```bash
# pve01 : création
pvecm create INFRA-CLUSTER --link0 10.1.240.11
# pve02 : join
pvecm add 10.1.240.11 --link0 10.1.240.12
# un des nœuds, qdevice rebranché (Raspberry Pi qdevice03)
pvecm qdevice setup 10.1.240.13
pvecm status                          # Quorate: Yes, 3 votes
```
Pour un seul nœud réinstallé dans un cluster vivant : procédure de re-join
dans `ansible/roles/pve_config/tasks/cluster.yml` (section 9).

### 8.5 Configuration des nœuds (`pve_config`)

```bash
make pve-config-check
make pve-config CONFIRM=yes
```
Dépôts, `/etc/hosts`, NTP, IQN iSCSI enregistré (masking du NAS), CHAP,
multipath, options du datacenter, stockages, job de backup de 02:00, comptes
API. Points d'attention :

- `pbs-store1` pointe sur la VM PBS, pas encore revenue : sa création peut
  échouer à ce stade. Relancer `make pve-config` après l'étape 8.6.
- le stockage `pbs-offsite` est créé avec la clé de chiffrement du vault :
  c'est lui qui permet la restauration de l'étape 8.7.
- le jeton `terraform@pve!iac` est recréé avec un **nouveau secret**, écrit
  dans `20-proxmox/terraform.tfvars` : le recopier dans
  `group_vars/pve/vault.yml` (`vault_pve_terraform_token`, le secret seul)
  et dans Vaultwarden. Même chose pour les jetons `monitoring@pve!exporter`
  et `packer@pve!pieric` (secrets dans `build/pve-tokens/`).

### 8.6 PBS du rack (VM 2400, `pbs_config`)

La VM PBS ne se sauvegarde pas elle-même (exclue du job de 02:00) : on la
**recrée vide**, on y installe PBS, et `pbs_config` lui rend sa config.

1. VM vide depuis le code (16 Gio système + 40 Gio datastore, `local-lvm` de
   pve02, même MAC) :
   ```bash
   make vms-tfvars && make vms-init
   make vms-plan       # doit montrer : pbs à créer (et rien d'autre de détruit)
   ```
   Appliquer seulement la VM PBS (Terraform dans Docker, comme le Makefile) :
   `terraform apply -target=proxmox_virtual_environment_vm.pbs`.
2. Monter l'ISO PBS 4.x (stockage `synology-iso`), installer sur le disque de
   16 Gio : IP `10.1.240.30/24`, passerelle `10.1.240.1`, nom
   `pbs.cloud-1.fun`. Clé `key/ansible.pub` pour l'utilisateur `ansible`
   (sudo), comme les autres VMs.
3. Disque de données : `sdb` en ext4, monté sur `/mnt/datastore/store1`
   (fstab). `pbs_config` refuse de créer le datastore sur le disque système.
4. ```bash
   make pbs-config-check
   make pbs-config CONFIRM=yes
   make pve-config CONFIRM=yes       # crée pbs-store1 s'il manquait
   ```
   `token.shadow` est restauré depuis le vault : le cluster garde le même
   secret pour `pbs-store1`. La synchro `offsite-push` (05:30) reprend avec
   la même clé.

### 8.7 Restauration des guests (depuis le PBS distant)

Le datastore local repart vide : restaurer depuis **`pbs-offsite`** (stockage
du cluster, clé de chiffrement dans le vault et dans Vaultwarden). Garder les
**mêmes VMID** et le stockage `synology-lvm` (pbs : `local-lvm`, mais il n'est
pas sauvegardé). Ordre : dhcp-dns (2401, DNS de tout le reste), vault-01
(2402), rproxy-int01 (2403), puis le reste.
```bash
# sur un nœud, pour chaque guest (dernier backup : pvesm list pbs-offsite)
qmrestore pbs-offsite:backup/vm/2401/<date> 2401 --storage synology-lvm
pct restore 2402 pbs-offsite:backup/ct/2402/<date> --storage synology-lvm
```
Les templates (8001-8005) sont dans les backups aussi ; sinon les
reconstruire : `make templates CONFIRM=yes` (`15-templates/README.md`).

### 8.8 Guests et HA (Terraform, état dans HCP)

Les VMs restaurées sont identiques à celles décrites dans `20-proxmox` ; la
HA (ressources et règles) n'est pas dans les backups.
```bash
make vms-plan      # attendu : rien à changer sur les guests, HA à créer
make vms-apply CONFIRM=yes
```
**Ne jamais appliquer un plan qui crée une VM restaurable** : sans bloc
`clone`, Terraform créerait une VM vide (seule exception voulue : la VM pbs,
étape 8.6). Restaurer d'abord, puis replanifier.

### 8.9 Configuration des VMs

```bash
make config-check
make config CONFIRM=yes
```

---

## 9. Pannes partielles

### Un nœud perdu (l'autre tourne)

La HA redémarre ses guests sur le nœud restant (règles `node-affinity` non
strictes). Le cluster garde le quorum grâce au qdevice (2 votes sur 3).

1. Réparer le matériel (RAID : étape 6, puis `make iso`).
2. Côté nœud survivant : `pvecm delnode <nœud>`, `rm -rf /etc/pve/nodes/<nœud>`.
3. `make install HOST=<nœud> CONFIRM=yes`.
4. Sur le nœud réinstallé : `pvecm add <IP survivant> --link0 <sa propre IP MGMT>`.
5. `make pve-config CONFIRM=yes` : il retrouve son IQN iSCSI (le masking du
   NAS refuse tout autre), le CHAP et le multipath ; les guests reviennent
   sur leur nœud habituel (règles `home-pve01` / `home-pve02`).
6. Si c'était **pve02** : la VM pbs (disque local) est perdue → étape 8.6.
7. `make vms-plan` : aucun changement attendu.

### Le PBS seul perdu

Étape 8.6 uniquement, rien à restaurer : les guests tournent. Le datastore
repart vide et se remplit au backup suivant (02:00) ; l'historique reste sur
le PBS distant.

### Le poste de contrôle perdu

Étape 1 : cloner le repo, mot de passe du vault et clé SSH depuis Bitwarden,
login HCP. Tout l'état utile est dans le repo (vaults) et dans HCP (état
Terraform), rien à reconstruire.

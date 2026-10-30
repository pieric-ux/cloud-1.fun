# cloud-1-iac — one target per step, in rebuild order (docs/runbook-point-zero.md).
# Read-only targets run as is; targets that change something need CONFIRM=yes
# (on top of the confirmation each playbook already asks for).
#
#   make help

ANSIBLE_DIR := ansible
PLAYBOOK    := cd $(ANSIBLE_DIR) && ansible-playbook
ISO_PORT    ?= 8080
# Terraform from the official image (no local install), same version as the
# one the code was validated with.
TERRAFORM   := docker run --rm -it -v $(CURDIR)/20-proxmox:/w -w /w hashicorp/terraform:1.9.8

# Refuse a target that changes something unless CONFIRM=yes is given.
define need_confirm
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "Changes $(1): preview first, then re-run with CONFIRM=yes"; exit 1; \
	fi
endef

# Refuse a per-host target without HOST=.
define need_host
	@if [ -z "$(HOST)" ]; then echo "HOST is required (e.g. HOST=pve02)"; exit 1; fi
endef

.DEFAULT_GOAL := help
.PHONY: help preflight lint \
	network network-check network-apply pfsense-backup \
	bootstrap iso media-test serve-iso install pve-config-check pbs-config-check \
	templates-check templates \
	vms-init vms-plan \
	config-check config

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

# ansible-lint has its own ansible-core: point it to the collections of the
# Ansible install too (site-packages of the Python ansible runs with).
ANSIBLE_PYTHON := $(shell sed -n '1s/^\#!//p' $$(command -v ansible) 2>/dev/null)
ANSIBLE_SITE   := $(shell $(ANSIBLE_PYTHON) -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null)

lint: ## Lint the Ansible code (ansible-lint, profile production)
	cd $(ANSIBLE_DIR) && ANSIBLE_COLLECTIONS_PATH=$$HOME/.ansible/collections:$(ANSIBLE_SITE) ansible-lint --offline

# --- Before a rebuild -------------------------------------------------------

preflight: ## Check the manual point zero (read-only, verdict at the end)
	$(PLAYBOOK) preflight.yml

# --- 00 network: switches + pfSense -----------------------------------------

network: ## Snapshot switches and pfSense (read-only) -> build/network/
	$(PLAYBOOK) 00-network.yml

network-check: ## Preview the network config as code (no change)
	$(PLAYBOOK) 00-network.yml --tags apply,pfsense-apply --check --diff

network-apply: ## Apply the network config as code (CONFIRM=yes)
	$(call need_confirm,the switches and pfSense)
	$(PLAYBOOK) 00-network.yml --tags apply,pfsense-apply \
		-e network_apply_confirm=true -e pfsense_apply_confirm=true

pfsense-backup: ## Store the pfSense config vault-encrypted in the repo
	$(PLAYBOOK) 00-network.yml --limit pfsense --tags pfsense-backup

# --- 10 bootstrap: bare metal through the iLO -------------------------------

bootstrap: ## Probe the iLOs and check the RAID (read-only)
	$(PLAYBOOK) 10-bootstrap.yml

iso: ## Build the auto-install ISO of every host (local, Docker)
	$(PLAYBOOK) 10-bootstrap.yml --tags build-iso

media-test: ## Mount then eject the stock ISO, no reboot (HOST=, CONFIRM=yes)
	$(call need_host)
	$(call need_confirm,the virtual media of $(HOST))
	$(PLAYBOOK) 10-bootstrap.yml --tags media-test --limit $(HOST)

serve-iso: ## Serve the prepared ISOs to the iLOs during an install
	cd 10-bootstrap/build && npx http-server -p $(ISO_PORT) -a 0.0.0.0

install: ## DESTRUCTIVE: reinstall Proxmox on one node (HOST=, CONFIRM=yes)
	$(call need_host)
	$(call need_confirm,$(HOST): its system disk is wiped)
	$(PLAYBOOK) 10-bootstrap.yml --tags install --limit $(HOST) -e pve_install_confirm=true

pve-config-check: ## Preview the Proxmox node configuration (no change)
	$(PLAYBOOK) 10-bootstrap.yml --tags pve-config --check --diff

pbs-config-check: ## Preview the Proxmox Backup Server configuration (no change)
	$(PLAYBOOK) 10-bootstrap.yml --tags pbs-config --check --diff

# --- 15 templates: Packer (local install: serves the answer files over HTTP
# to the VM, on the address of this machine seen from VLAN 240) -------------
TEMPLATES_DIR := 15-templates

templates-check: ## Validate the Packer templates (local, no API call)
	cd $(TEMPLATES_DIR) && packer init . && packer fmt -check . \
		&& packer validate -var-file=templates.pkrvars.example.hcl .

templates: ## Build the VM templates (CONFIRM=yes, needs 15-templates/templates.pkrvars.hcl; ONLY='ubuntu2404.*' for one)
	$(call need_confirm,the cluster: new template VMs)
	cd $(TEMPLATES_DIR) && packer build -parallel-builds=1 \
		-var-file=templates.pkrvars.hcl $(if $(ONLY),-only='$(ONLY)') .

# --- 20 proxmox: guests with Terraform (read-only for now) ------------------

vms-init: ## Download the Terraform provider (local)
	$(TERRAFORM) init

vms-plan: ## List the cluster VMs, change nothing (needs 20-proxmox/terraform.tfvars)
	$(TERRAFORM) plan

# --- 30 config: OS configuration of the VMs ---------------------------------

config-check: ## Preview the OS configuration of the VMs (no change)
	$(PLAYBOOK) 30-config.yml --check --diff

config: ## Apply the OS configuration of the VMs (CONFIRM=yes)
	$(call need_confirm,the VMs)
	$(PLAYBOOK) 30-config.yml

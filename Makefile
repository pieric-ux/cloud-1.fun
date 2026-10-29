# cloud-1-iac — one target per step, in rebuild order (docs/runbook-point-zero.md).
# Read-only targets run as is; targets that change something need CONFIRM=yes
# (on top of the confirmation each playbook already asks for).
#
#   make help

ANSIBLE_DIR := ansible
PLAYBOOK    := cd $(ANSIBLE_DIR) && ansible-playbook
ISO_PORT    ?= 8080

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
.PHONY: help preflight \
	network network-check network-apply pfsense-backup \
	bootstrap iso media-test serve-iso install \
	config

help: ## List the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

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

# --- 30 config: OS configuration of the VMs ---------------------------------

config: ## Apply the OS configuration of the VMs (CONFIRM=yes)
	$(call need_confirm,the VMs)
	$(PLAYBOOK) 30-config.yml

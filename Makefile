# OpenTofu + Ansible で開発用 VM をプロビジョニングする
#
#   make up                 # Proxmox に VM を作ってセットアップまで
#   make up ENV=docker      # Docker のテストノードで同じことをする
#   make test               # Docker で up -> verify -> down
#
# 変数は .env にも書ける (例: ENV=docker, PROXMOX_VE_API_TOKEN=...)

SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

-include .env
export

ENV          ?= proxmox
TOFU         ?= tofu
UV           ?= uv
TOFU_VERSION ?= 1.13.1

TOFU_DIR   := tofu/envs/$(ENV)
INVENTORY  := ansible/inventory/$(ENV).yml
STATE_DIR  := .state
KNOWN_HOSTS := $(STATE_DIR)/known_hosts_$(ENV)

# 1 にすると tofu apply / destroy の確認を省略する
AUTO_APPROVE ?=
TOFU_APPROVE := $(if $(filter 1 true yes,$(AUTO_APPROVE)),-auto-approve,)

# ansible-playbook に追加で渡す引数 (例: ARGS="--tags uv -l dev01")
ARGS ?=

export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg
# VM を作り直すとホスト鍵が変わるので、プロジェクト専用の known_hosts を使う
export ANSIBLE_SSH_ARGS := -o ControlMaster=auto -o ControlPersist=60s \
	-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$(CURDIR)/$(KNOWN_HOSTS)

ANSIBLE          := $(UV) run ansible
ANSIBLE_PLAYBOOK := $(UV) run ansible-playbook -i $(INVENTORY)

ifeq ($(filter $(ENV),proxmox docker),)
$(error ENV は proxmox か docker を指定してください (ENV=$(ENV)))
endif

.DEFAULT_GOAL := help

##@ ヘルプ

.PHONY: help
help: ## このヘルプを表示する
	@awk 'BEGIN {FS = ":.*##"; printf "使い方: make \033[36m<target>\033[0m [ENV=proxmox|docker]\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ セットアップ

.PHONY: setup
setup: ## Python 環境 (Ansible) を作成し、必要なツールを確認する
	$(UV) sync
	@command -v $(TOFU) >/dev/null || { echo "tofu がありません。make install-tofu を実行してください"; exit 1; }
	@$(TOFU) version | head -1
	@$(UV) run ansible --version | head -1

.PHONY: install-tofu
install-tofu: ## OpenTofu を ~/.local/bin にインストールする (TOFU_VERSION で指定)
	curl -fsSL https://get.opentofu.org/install-opentofu.sh -o $(STATE_DIR)/install-opentofu.sh --create-dirs
	sh $(STATE_DIR)/install-opentofu.sh --install-method standalone \
		--opentofu-version $(TOFU_VERSION) --install-path $(HOME)/.local/bin --symlink-path -
	rm -f $(STATE_DIR)/install-opentofu.sh
	$(HOME)/.local/bin/tofu version

##@ OpenTofu

.PHONY: init
init: ## tofu init
	$(TOFU) -chdir=$(TOFU_DIR) init

$(TOFU_DIR)/.terraform:
	$(TOFU) -chdir=$(TOFU_DIR) init

.PHONY: plan
plan: $(TOFU_DIR)/.terraform ## tofu plan
	$(TOFU) -chdir=$(TOFU_DIR) plan

.PHONY: apply
apply: $(TOFU_DIR)/.terraform ## tofu apply (VM を作成) してインベントリを書き出す
	$(TOFU) -chdir=$(TOFU_DIR) apply $(TOFU_APPROVE)
	@$(MAKE) --no-print-directory inventory

.PHONY: destroy
destroy: $(TOFU_DIR)/.terraform ## tofu destroy (VM を削除)
	$(TOFU) -chdir=$(TOFU_DIR) destroy $(TOFU_APPROVE)
	rm -f $(INVENTORY) $(KNOWN_HOSTS)

.PHONY: output
output: ## tofu output (VM の IP など)
	$(TOFU) -chdir=$(TOFU_DIR) output vm_ips

.PHONY: password
password: ## コンソール (Proxmox Web UI) ログイン用のパスワードを表示する
	@$(TOFU) -chdir=$(TOFU_DIR) output -raw vm_password; echo

.PHONY: inventory
inventory: ## tofu の出力から Ansible インベントリを生成する
	@mkdir -p $(STATE_DIR)
	$(TOFU) -chdir=$(TOFU_DIR) output -json ansible_inventory > $(INVENTORY).tmp
	@mv $(INVENTORY).tmp $(INVENTORY)
	@echo "wrote $(INVENTORY)"

##@ Ansible

.PHONY: wait
wait: ## VM に SSH できるようになるまで待つ
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/wait.yml

.PHONY: ping
ping: ## 疎通確認
	$(ANSIBLE) all -i $(INVENTORY) -m ansible.builtin.ping

.PHONY: provision
provision: ## SSH 鍵登録・uv・opencode などをセットアップする
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/site.yml $(ARGS)

.PHONY: check
check: ## provision を dry-run (--check --diff) する
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/site.yml --check --diff $(ARGS)

.PHONY: verify
verify: ## インストールしたツールが使えるか確認する
	$(ANSIBLE_PLAYBOOK) ansible/playbooks/verify.yml $(ARGS)

.PHONY: ssh
ssh: ## VM に SSH する (HOST=dev01、省略時は先頭のホスト)
	ssh $(ANSIBLE_SSH_ARGS) $$($(UV) run python scripts/ssh_args.py $(INVENTORY) "$(HOST)")

##@ まとめて実行

.PHONY: up
up: apply wait provision ## apply -> wait -> provision

.PHONY: down
down: destroy ## destroy の別名

.PHONY: test
test: ## Docker で up -> verify -> 冪等性チェック -> down を実行する
	$(MAKE) --no-print-directory ENV=docker AUTO_APPROVE=1 up
	$(MAKE) --no-print-directory ENV=docker verify
	$(MAKE) --no-print-directory ENV=docker idempotency
	$(MAKE) --no-print-directory ENV=docker AUTO_APPROVE=1 down

.PHONY: idempotency
idempotency: ## provision を再実行して changed=0 であることを確認する
	@$(ANSIBLE_PLAYBOOK) ansible/playbooks/site.yml $(ARGS) | tee $(STATE_DIR)/idempotency.log
	@grep -qE 'changed=[1-9]' $(STATE_DIR)/idempotency.log \
		&& { echo "NG: 2 回目の実行で変更が発生しました"; exit 1; } || echo "OK: 冪等です"

##@ 開発

.PHONY: fmt
fmt: ## tofu fmt
	$(TOFU) fmt -recursive tofu

.PHONY: lint
lint: ## tofu fmt -check / validate と ansible-lint
	$(TOFU) fmt -check -recursive tofu
	for d in tofu/envs/*/; do \
		$(TOFU) -chdir=$$d init -backend=false -input=false >/dev/null && $(TOFU) -chdir=$$d validate || exit 1; \
	done
	cd ansible && $(UV) run ansible-lint playbooks roles

.PHONY: clean
clean: ## 生成物 (インベントリ・.state・.terraform) を削除する。tfstate は残す
	rm -rf $(STATE_DIR) ansible/inventory/*.yml tofu/envs/*/.terraform

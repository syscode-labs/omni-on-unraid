BIN_DIR ?= dist
INSTALL_DIR ?= $(HOME)/.local/bin
OMNI_TUI_BIN ?= omni-on-unraid
GO ?= go
GO_ENV ?= env -u GOROOT GOCACHE=$(CURDIR)/.cache/go-build

.PHONY: help build install uninstall tui release-check snapshot infra-prepare-image infra-check infra-init infra-plan infra-apply infra-destroy doctor render up down backup restore deploy-remote omni-tools-shell omni-provider-apply omni-provider-status omni-provider-logs omni-provider-down omni-machineclass-apply omni-cluster-apply omni-cluster-status omni-lab-provision stack-provision provider provider-status provider-logs provider-down mc cluster status lab tools

help:
	@printf '%s\n' \
		'Install targets:' \
		'  make build           Build TUI package into dist/' \
		'  make install         Install TUI to ~/.local/bin/omni-on-unraid' \
		'  make uninstall       Remove installed TUI' \
		'  make tui             Run TUI without installing' \
		'  make release-check   Validate GoReleaser config' \
		'  make snapshot        Build local release snapshot' \
		'' \
		'Omni cluster targets:' \
		'  make provider        Register/start Omni libvirt provider' \
		'  make provider-status Show local provider container status' \
		'  make provider-logs   Tail provider logs' \
		'  make provider-down   Stop provider container' \
		'  make mc              Apply Omni MachineClasses' \
		'  make cluster         Validate/sync Omni cluster template' \
		'  make status          Show Omni cluster template status' \
		'  make lab             Run provider + machine classes + cluster' \
		'' \
		'Omni service VM targets:' \
		'  make deploy-remote   Sync/apply Omni service VM deployment' \
		'  make stack-provision Bootstrap Omni service VM on Unraid'

build:
	$(GO_ENV) $(GO) build -o "$(BIN_DIR)/$(OMNI_TUI_BIN)" ./cmd/omni-tui

install: build
	mkdir -p "$(INSTALL_DIR)"
	cp "$(BIN_DIR)/$(OMNI_TUI_BIN)" "$(INSTALL_DIR)/$(OMNI_TUI_BIN)"
	@printf 'installed %s\n' "$(INSTALL_DIR)/$(OMNI_TUI_BIN)"

uninstall:
	rm -f "$(INSTALL_DIR)/$(OMNI_TUI_BIN)"
	@printf 'removed %s\n' "$(INSTALL_DIR)/$(OMNI_TUI_BIN)"

tui:
	$(GO_ENV) $(GO) run ./cmd/omni-tui

release-check:
	goreleaser check

snapshot:
	goreleaser release --snapshot --clean

infra-prepare-image:
	mise run infra:prepare-image

infra-check:
	mise run infra:check

infra-init:
	mise run infra:init

infra-plan:
	mise run infra:plan

infra-apply:
	mise run infra:apply

infra-destroy:
	mise run infra:destroy

doctor:
	mise run omni:doctor

render:
	mise run omni:render

up:
	mise run omni:up

down:
	mise run omni:down

backup:
	mise run omni:backup

restore:
	@if [ -z "$(BACKUP)" ]; then \
		echo "Set BACKUP=/path/to/backup.tar.gz" >&2; \
		exit 1; \
	fi
	BACKUP="$(BACKUP)" mise run omni:restore

deploy-remote:
	mise run omni:deploy-remote

omni-tools-shell:
	mise run omni:tools:shell

omni-provider-apply:
	mise run omni:provider:apply

omni-provider-status:
	mise run omni:provider:status

omni-provider-logs:
	mise run omni:provider:logs

omni-provider-down:
	mise run omni:provider:down

omni-machineclass-apply:
	mise run omni:machineclass:apply

omni-cluster-apply:
	mise run omni:cluster:apply

omni-cluster-status:
	mise run omni:cluster:status

omni-lab-provision:
	mise run omni:lab:provision

stack-provision:
	mise run stack:provision

provider: omni-provider-apply

provider-status: omni-provider-status

provider-logs: omni-provider-logs

provider-down: omni-provider-down

mc: omni-machineclass-apply

cluster: omni-cluster-apply

status: omni-cluster-status

lab: omni-lab-provision

tools: omni-tools-shell

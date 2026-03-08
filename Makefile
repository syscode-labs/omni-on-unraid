.PHONY: infra-prepare-image infra-check infra-init infra-plan infra-apply infra-destroy doctor render up down backup restore deploy-remote stack-provision

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

stack-provision:
	mise run stack:provision

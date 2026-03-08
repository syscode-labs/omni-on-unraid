.PHONY: doctor render up down backup restore apply

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

apply:
	mise run omni:apply

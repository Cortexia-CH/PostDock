###
# Usual suspects... docker management

ps:
	docker ps --format 'table {{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}'

init: check-env ssh-keys
	docker network create -d overlay ${POSTGRES_NETWORK} || true

config: check-env
	DOCKER_TAG=$(DOCKER_TAG) \
	SUBDOMAIN=$(SUBDOMAIN) \
	DOMAIN=$(DOMAIN) \
		docker-compose \
			-f docker-compose.yml \
		config > docker-stack.yml

pull: config check-keys
	docker-compose -f docker-stack.yml pull $(services)
	docker-compose -f docker-stack.yml build --pull $(services)

up: check-stack check-keys
	docker-compose -f docker-stack.yml up -d $(services)

down: check-stack
	docker-compose -f docker-stack.yml down

stop: check-stack
	docker-compose -f docker-stack.yml stop $(services)

logs: check-stack
	docker-compose -f docker-stack.yml logs --tail 20 -f $(services)

build: config check-env check-keys
	docker-compose -f docker-stack.yml build $(services)

push: check-env ssh-keys
	docker login
	# update tags
	git tag -f prod
	git push --tags --force

	# build docker image
	DOCKER_TAG=prod \
		SUBDOMAIN=pgcluster \
		DOMAIN=cortexia.io \
		docker-compose build $(services)
	DOCKER_TAG=prod \
		SUBDOMAIN=pgcluster \
		DOMAIN=cortexia.io \
		docker-compose push $(services)


###
# Helpers for initialization

check-env:
# raise an error if .env file does not exist
ifeq ($(wildcard .env),)
	cp .sample.env .env
	@echo "Generated \033[32m.env\033[0m"
	@echo "  \033[31m>> Check its default values\033[0m"
	@exit 1
else
include .env
export
endif

check-stack: check-env
ifeq ($(wildcard docker-stack.yml),)
	@echo "docker-stack.yml file is missing"
	@echo ">> use \033[1mmake \033[32mconfig\033[0m"
	@exit 1
endif

check-keys:
# create ssh keys if they do not exist yet
ifeq ($(wildcard src/ssh/keys/id_rsa),)
	@echo "no ssh-keys found. Creating it..."
	make ssh-keys
endif

ssh-keys:
	mkdir -p src/ssh/keys
	rm src/ssh/keys/id_rsa* || true
	cd src/ssh/keys && ssh-keygen -t rsa -C "internal@pgpool.com" -f id_rsa -N ''
	chmod 500 src/ssh/keys/id_rsa
	ssh-add src/ssh/keys/id_rsa


###
# Local administation

status: pg-master pgpool-enough barman-check barman-list-backup

readme:
	open "doc/Forming a PostgreSQL cluster within Kubernetes - Dmitriy Paunin - Medium.pdf"

# PostgreSQL

pg: pg-live pg-master

pg-map: check-env
	@echo "\r\n--- pg-map ---"
	docker-compose -f docker-stack.yml exec pgmaster bash -c \
		'gosu postgres psql $(REPLICATION_DB) -c "SELECT * FROM $$(get_repmgr_schema).$(REPMGR_NODES_TABLE)"'

pg-live: check-env
	@echo "\r\n--- pg-live ---"
	docker-compose -f docker-stack.yml exec pgmaster bash -c \
		'gosu postgres repmgr cluster show'

pg-master: check-env
	@echo "\r\n--- pg-master ---"
	docker-compose -f docker-stack.yml exec pgmaster bash -c \
		'/usr/local/bin/cluster/healthcheck/is_major_master.sh'

# pgpool

pgpool: pgpool-status pgpool-enough pgpool-write-mode

pgpool-status: check-env
	@echo "\r\n--- pgpool-status ---"
	docker-compose -f docker-stack.yml exec pgpool bash -c \
		'PGPASSWORD=$(CHECK_PASSWORD) psql -h pgpool -U $(CHECK_USER) template1 -c "show pool_nodes"'

pgpool-enough: check-env
	@echo "\r\n--- pgpool-enough ---"
	docker-compose -f docker-stack.yml exec pgpool bash -c \
		'/usr/local/bin/pgpool/has_enough_backends.sh'

pgpool-write-mode: check-env
	@echo "\r\n--- pgpool-write-mode ---"
	docker-compose -f docker-stack.yml exec pgpool bash -c \
		'/usr/local/bin/pgpool/has_write_node.sh'


# Barman

barman-list-server: check-env
	@echo "\r\n--- barman-list-server ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman list-server'

barman-check-all: check-env
	@echo "\r\n--- barman-check-all ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman check all'

barman-backup-all: check-env
	@echo "\r\n--- barman-backup-all ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman backup all'

barman-diagnose: check-env
	@echo "\r\n--- barman-diagnose ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman diagnose'

# Barman > server
# (All executed on `barman list-server --minimal`, i.e. pgmaster)

barman: barman-show barman-status barman-check barman-list-backup

barman-check: check-env
	@echo "\r\n--- barman-check ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman check `barman list-server --minimal`'

barman-status: check-env
	@echo "\r\n--- barman-status ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman status `barman list-server --minimal`'

barman-replication-status: check-env
	@echo "\r\n--- barman-replication-status ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman replication-status `barman list-server --minimal`'

barman-show: check-env
	@echo "\r\n--- barman-show ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman show-server `barman list-server --minimal`'

barman-list-backup: check-env
	@echo "\r\n--- barman-list-backup ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman list-backup `barman list-server --minimal`'


# Barman > backup 
# (All executed on `barman list-server --minimal`, i.e. pgmaster)

barman-backup: check-env
	@echo "\r\n--- barman-backup ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman backup `barman list-server --minimal`'

barman-check-backup: check-env
	@echo "\r\n--- barman-check-backup ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman check-backup `barman list-server --minimal` $(BACKUP_ID)'

barman-show-backup: check-env
	@echo "\r\n--- barman-show-backup ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman show-backup `barman list-server --minimal` $(BACKUP_ID)'

barman-delete-backup: check-env
	@echo "\r\n--- barman-delete-backup ---"
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman check-backup `barman list-server --minimal` $(BACKUP_ID)'

barman-fix-wal:
	# see for explanations:
	# https://groups.google.com/forum/#!topic/pgbarman/M-eFUCA1nHA
	docker-compose -f docker-stack.yml exec pgbackup bash -c \
		'barman switch-xlog --force `barman list-server --minimal`'

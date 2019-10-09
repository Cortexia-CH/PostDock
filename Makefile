# environment

# BACKUP_ID is used to specify which backup should be the target of given backup command, for instance:
# $ BACKUP_ID=20190924T125045 make barman-check-backup
#
# All ids can be listed with
# $ make barman-list-backup
#
# Barman allows you to use special keywords to identify a specific backup:
# - last/latest: identifies the newest backup in the catalog
# - first/oldest: identifies the oldest backup in the catalog
BACKUP_ID ?= oldest

readme:
	open "doc/Forming a PostgreSQL cluster within Kubernetes - Dmitriy Paunin - Medium.pdf"

check-env:
# raise an error if .env file does not exist
ifeq ($(wildcard .env),)
	cp .sample.env .env
	@echo "Generated .env"
	@echo ".env file is missing. Create it first by calling make init"
	@exit 1
else
include .env
export
endif

check-keys:
# create ssh keys if they do not exist yet
ifeq ($(wildcard src/ssh/keys/id_rsa),)
	@echo "no ssh-keys found. Creating it..."
	make ssh-keys
endif

init:
ifeq ($(wildcard .env),)
	cp .sample.env .env
	make ssh-keys
endif

ssh-keys:
	mkdir -p src/ssh/keys
	rm src/ssh/keys/id_rsa* || true
	cd src/ssh/keys && ssh-keygen -t rsa -C "internal@pgpool.com" -f id_rsa -N ''

vars: check-env check-keys
	@echo 'postgres'
	@echo '  POSTGRES_PASSWORD: $(POSTGRES_PASSWORD)'
	@echo '  POSTGRES_USER: $(POSTGRES_USER)'
	@echo '  POSTGRES_DB: $(POSTGRES_DB)'
	@echo '  DB_USERS: $(DB_USERS)'
	@echo ''
	@echo 'pgpool'
	@echo '  PCP_USER: $(PCP_USER)'
	@echo '  PCP_PASSWORD: $(PCP_PASSWORD)'
	@echo '  CHECK_USER: $(CHECK_USER)'
	@echo '  CHECK_PASSWORD: $(CHECK_PASSWORD)'
	@echo ''
	@echo 'pgadmin'
	@echo '  PGADMIN_LISTEN_PORT: $(PGADMIN_LISTEN_PORT)'
	@echo '  PGADMIN_DEFAULT_EMAIL: $(PGADMIN_DEFAULT_EMAIL)'
	@echo '  PGADMIN_DEFAULT_PASSWORD: $(PGADMIN_DEFAULT_PASSWORD)'
	@echo ''
	@echo 'barman'
	@echo '  CLUSTER_NAME: $(CLUSTER_NAME)'
	@echo '  REPLICATION_USER: $(REPLICATION_USER)'
	@echo '  REPLICATION_PASSWORD: $(REPLICATION_PASSWORD)'
	@echo '  REPLICATION_HOST: $(REPLICATION_HOST)'
	@echo '  REPLICATION_DB: $(REPLICATION_DB)'
	@echo '  REPMGR_NODES_TABLE: $(REPMGR_NODES_TABLE)'

status: pg-master pgpool-enough barman-check barman-list-backup

# docker management

login:
	docker login

ps:
	docker ps --format 'table {{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}'

config-local: check-env
	DOCKER_TAG=latest \
	SUBDOMAIN=pgcluster \
	DOMAIN=local \
	docker-compose \
		-f docker-compose.common.yml \
		-f docker-compose.build.yml \
		-f docker-compose.dev.yml \
	config > docker-stack.yml

pull: config-local
	docker-compose -f docker-stack.yml pull $(services)
	docker-compose -f docker-stack.yml build --pull $(services)

build: config-local check-env ssh-keys
	docker-compose -f docker-stack.yml build $(services)

up: config-local check-env check-keys
	docker-compose -f docker-stack.yml up -d $(services)

down:
	docker-compose -f docker-stack.yml down $(services)

stop:
	docker-compose -f docker-stack.yml stop $(services)

logs: up
	docker-compose -f docker-stack.yml logs --tail 20 -f $(services)


## Release

push-qa: check-env login
	# update tags
	git tag -f qa
	git push --tags --force

	# compile docker-compose file
	DOCKER_TAG=qa \
		SUBDOMAIN=pgcluster-qa \
		DOMAIN=cortexia.io \
		docker-compose \
			-f docker-compose.common.yml \
			-f docker-compose.images.yml \
			-f docker-compose.networks.yml \
			-f docker-compose.volumes-placement.yml \
			-f docker-compose.build.yml \
		config > docker-stack.yml

	# build docker image
	DOCKER_TAG=qa docker-compose -f docker-stack.yml build $(services)
	DOCKER_TAG=qa docker-compose -f docker-stack.yml push $(services)

deploy-qa: check-env
	DOCKER_TAG=qa \
		SUBDOMAIN=pgcluster-qa \
		DOMAIN=cortexia.io \
		STACK_NAME=pgcluster-qa \
		TRAEFIK_PUBLIC_TAG=${TRAEFIK_PUBLIC_TAG} \
		docker-compose \
			-f docker-compose.common.yml \
			-f docker-compose.images.yml \
			-f docker-compose.networks.yml \
			-f docker-compose.volumes-placement.yml \
			-f docker-compose.deploy.yml \
		config > docker-stack.yml

	docker-auto-labels docker-stack.yml
	docker stack deploy -c docker-stack.yml --with-registry-auth pgcluster-qa


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
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman list-server'

barman-check-all: check-env
	@echo "\r\n--- barman-check-all ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman check all'

barman-backup-all: check-env
	@echo "\r\n--- barman-backup-all ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman backup all'

barman-diagnose: check-env
	@echo "\r\n--- barman-diagnose ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman diagnose'

# Barman > server
# (All executed on `barman list-server --minimal`, i.e. pgmaster)

barman: barman-show barman-status barman-check barman-list-backup

barman-check: check-env
	@echo "\r\n--- barman-check ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman check `barman list-server --minimal`'

barman-status: check-env
	@echo "\r\n--- barman-status ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman status `barman list-server --minimal`'

barman-replication-status: check-env
	@echo "\r\n--- barman-replication-status ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman replication-status `barman list-server --minimal`'

barman-show: check-env
	@echo "\r\n--- barman-show ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman show-server `barman list-server --minimal`'

barman-list-backup: check-env
	@echo "\r\n--- barman-list-backup ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman list-backup `barman list-server --minimal`'


# Barman > backup 
# (All executed on `barman list-server --minimal`, i.e. pgmaster)

barman-backup: check-env
	@echo "\r\n--- barman-backup ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman backup `barman list-server --minimal`'

barman-check-backup: check-env
	@echo "\r\n--- barman-check-backup ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman check-backup `barman list-server --minimal` $(BACKUP_ID)'

barman-show-backup: check-env
	@echo "\r\n--- barman-show-backup ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman show-backup `barman list-server --minimal` $(BACKUP_ID)'

barman-delete-backup: check-env
	@echo "\r\n--- barman-delete-backup ---"
	docker-compose -f docker-stack.yml exec backup bash -c \
		'barman check-backup `barman list-server --minimal` $(BACKUP_ID)'

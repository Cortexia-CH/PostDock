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
	@echo ".env file is missing. Create it first by calling make init"
	@exit 1
else
include .env
export
endif

check-keys:
# create ssh keys if they do not exist yet
ifeq ($(wildcard /tmp/.ssh/keys/id_rsa),)
	@echo "no ssh-keys found. Creating it..."
	make ssh-keys
endif

init:
ifeq ($(wildcard .env),)
	cp .env.sample .env
	make ssh-keys
endif

ssh-keys:
	mkdir -p /tmp/.ssh/keys
	cd /tmp/.ssh/keys && ssh-keygen -t rsa -C "internal@pgpool.com" -f /tmp/.ssh/keys/id_rsa

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

pull:
	docker-compose -f ./docker-compose/latest-simple.yml pull $(services)
	docker-compose -f ./docker-compose/latest-simple.yml build --pull $(services)

build: check-env check-keys
	docker-compose -f ./docker-compose/latest-simple.yml build $(services)

up:
	docker-compose -f ./docker-compose/latest-simple.yml up -d $(services)

stop:
	docker-compose -f ./docker-compose/latest-simple.yml stop $(services)

down:
	docker-compose -f ./docker-compose/latest-simple.yml down $(services)

logs: up
	docker-compose -f ./docker-compose/latest-simple.yml logs --tail 20 -f $(services)

ps:
	docker ps --format 'table {{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}'


# PostgreSQL

pg: pg-live pg-master

pg-map: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec pgmaster bash -c \
		'gosu postgres psql $(REPLICATION_DB) -c "SELECT * FROM $$(get_repmgr_schema).$(REPMGR_NODES_TABLE)"'

pg-live: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec pgmaster bash -c \
		'gosu postgres repmgr cluster show'

pg-master: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec pgmaster bash -c \
		'/usr/local/bin/cluster/healthcheck/is_major_master.sh'


# pgpool

pgpool: pgpool-status pgpool-enough pgpool-write-mode

pgpool-status: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec pgpool bash -c \
		'PGPASSWORD=$(CHECK_PASSWORD) psql -h pgpool -U $(CHECK_USER) template1 -c "show pool_nodes"'

pgpool-enough: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec pgpool bash -c \
		'/usr/local/bin/pgpool/has_enough_backends.sh'

pgpool-write-mode: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec pgpool bash -c \
		'/usr/local/bin/pgpool/has_write_node.sh'


# Barman

barman-list-server: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman list-server'

barman-check-all: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman check all'

barman-backup-all: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman backup all'

barman-diagnose: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman diagnose'

# Barman > server
# (All executed on `barman list-server --minimal`, i.e. pgmaster)

barman: barman-show barman-status barman-check barman-list-backup

barman-check: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman check `barman list-server --minimal`'

barman-status: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman status `barman list-server --minimal`'

barman-replication-status: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman replication-status `barman list-server --minimal`'

barman-show: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman show-server `barman list-server --minimal`'

barman-list-backup: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman list-backup `barman list-server --minimal`'


# Barman > backup 
# (All executed on `barman list-server --minimal`, i.e. pgmaster)

barman-backup: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman backup `barman list-server --minimal`'

barman-check-backup: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman check-backup `barman list-server --minimal` $(BACKUP_ID)'

barman-show-backup: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman show-backup `barman list-server --minimal` $(BACKUP_ID)'

barman-delete-backup: check-env
	docker-compose -f ./docker-compose/latest-simple.yml exec backup bash -c \
		'barman check-backup `barman list-server --minimal` $(BACKUP_ID)'

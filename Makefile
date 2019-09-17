# environment

check-env:
ifeq ($(wildcard .env),)
	@echo ".env file is missing. Create it first by calling make init"
	@exit 1
else
include .env
export
endif

init:
ifeq ($(wildcard .env),)
	cp .env.sample .env
	make ssh-keys
endif

vars: check-env
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
	@echo 'barman'
	@echo '  CLUSTER_NAME: $(CLUSTER_NAME)'
	@echo '  REPLICATION_USER: $(REPLICATION_USER)'
	@echo '  REPLICATION_PASSWORD: $(REPLICATION_PASSWORD)'
	@echo '  REPLICATION_HOST: $(REPLICATION_HOST)'
	@echo '  REPLICATION_DB: $(REPLICATION_DB)'
	@echo '  REPMGR_NODES_TABLE: $(REPMGR_NODES_TABLE)'


ssh-keys:
	mkdir -p /tmp/.ssh/keys
	cd /tmp/.ssh/keys && ssh-keygen -t rsa -C "internal@pgpool.com" -f /tmp/.ssh/keys/id_rsa

# docker management

pull:
	docker-compose -f ./docker-compose/latest.yml pull
	docker-compose -f ./docker-compose/latest.yml build --pull

build:
	docker-compose -f ./docker-compose/latest.yml build

up:
	docker-compose -f ./docker-compose/latest.yml up -d pgmaster pgslave1 pgslave2 pgslave3 pgslave4 pgpool backup

stop:
	docker-compose -f ./docker-compose/latest.yml stop

down:
	docker-compose -f ./docker-compose/latest.yml down

logs: up
	docker-compose -f ./docker-compose/latest.yml logs --tail 20 -f $(names)

ps:
	docker ps --format 'table {{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}'


# PostgreSQL

pg-map: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgmaster bash -c \
		'gosu postgres psql $(REPLICATION_DB) -c "SELECT * FROM $$(get_repmgr_schema).$(REPMGR_NODES_TABLE)"'

pg-live: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgmaster bash -c \
		'gosu postgres repmgr cluster show'

pg-master: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgmaster bash -c \
		'/usr/local/bin/cluster/healthcheck/is_major_master.sh'


# pgpool

pgpool-status: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgpool bash -c \
		'PGPASSWORD=$(CHECK_PASSWORD) psql -U $(CHECK_USER) template1 -c "show pool_nodes"'

pgpool-enough: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgpool bash -c \
		'/usr/local/bin/pgpool/has_enough_backends.sh'

pgpool-write-mode: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgpool bash -c \
		'/usr/local/bin/pgpool/has_write_node.sh'


# Barman

barman-list-server: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman list-server'

barman-check-all: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman check all'

barman-backup-all: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman backup all'

barman-diagnose: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman diagnose'

# Barman > server

barman-check: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman check `barman list-server --minimal`'

barman-status: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman status `barman list-server --minimal`'

barman-show: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman show-server `barman list-server --minimal`'

barman-backup: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman backup `barman list-server --minimal`'

barman-list-backup: check-env
	docker-compose -f ./docker-compose/latest.yml exec backup bash -c \
		'barman list-backup `barman list-server --minimal`'

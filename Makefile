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
	@echo '  REPLICATION_USER: $(REPLICATION_USER)'
	@echo '  REPLICATION_PASSWORD: $(REPLICATION_PASSWORD)'
	@echo '  REPLICATION_HOST: $(REPLICATION_HOST)'
	@echo '  REPMGR_NODES_TABLE: $(REPMGR_NODES_TABLE)'


# docker management

up:
	docker-compose -f ./docker-compose/latest.yml up pgmaster pgslave1 pgslave2 pgslave3 pgslave4 pgpool backup

start:
	docker-compose -f ./docker-compose/latest.yml up -d pgmaster pgslave1 pgslave2 pgslave3 pgslave4 pgpool backup

stop:
	docker-compose -f ./docker-compose/latest.yml stop

down:
	docker-compose -f ./docker-compose/latest.yml down


# control and maintenance

logs:
	docker-compose -f ./docker-compose/latest.yml logs --tail 20 -f $(names)

map: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgmaster bash -c \
		'gosu postgres psql $(REPLICATION_DB) -c "SELECT * FROM $$(get_repmgr_schema).$(REPMGR_NODES_TABLE)"'

live: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgmaster bash -c \
		'gosu postgres repmgr cluster show'

status: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgmaster bash -c \
		'PGPASSWORD=$(CHECK_PASSWORD) psql -U $(CHECK_USER) template1 -c "show pool_nodes"'

primary: check-env
	docker-compose -f ./docker-compose/latest.yml exec pgpool bash -c \
		'/usr/local/bin/pgpool/has_write_node.sh'

ps:
	docker ps --format 'table {{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}'

COMPOSE_FILE := srcs/docker-compose.yml
COMPOSE := docker compose -f $(COMPOSE_FILE)

DATA_DIR := /home/tsargsya/data
MARIADB_DIR := $(DATA_DIR)/mariadb
WORDPRESS_DIR := $(DATA_DIR)/wordpress

CERTIFICATE_SCRIPT := ./tools/generate_certificates.sh

all: prepare
	$(COMPOSE) up --build -d

prepare:
	mkdir -p $(MARIADB_DIR)
	mkdir -p $(WORDPRESS_DIR)
	$(CERTIFICATE_SCRIPT)

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --remove-orphans

fclean:
	$(COMPOSE) down --rmi all --volumes --remove-orphans
	sudo rm -rf $(DATA_DIR)

re: fclean
	$(MAKE) all

.PHONY: all prepare down clean fclean re
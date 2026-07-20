COMPOSE_FILE := srcs/docker-compose.yml
DATA_DIR := /home/tsargsya/data

all: prepare
	docker compose -f $(COMPOSE_FILE) up -d --build

prepare:
	mkdir -p $(DATA_DIR)/mariadb

down:
	docker compose -f $(COMPOSE_FILE) down

clean: down

fclean:
	docker compose -f $(COMPOSE_FILE) down \
		--rmi all \
		--volumes \
		--remove-orphans

re: fclean all

.PHONY: all prepare down clean fclean re

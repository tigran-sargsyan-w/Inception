COMPOSE_FILE := srcs/docker-compose.yml

all:
	docker compose -f $(COMPOSE_FILE) up -d --build

down:
	docker compose -f $(COMPOSE_FILE) down

clean: down

fclean:
	docker compose -f $(COMPOSE_FILE) down \
		--rmi all \
		--volumes \
		--remove-orphans

re: fclean all

.PHONY: all down clean fclean re

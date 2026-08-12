# **************************************************************************** #
#                                  Makefile                                    #
# **************************************************************************** #

NAME := inception

COMPOSE_FILE := srcs/docker-compose.yml
COMPOSE := docker compose -f $(COMPOSE_FILE)

# -------------------------------
# Data directories
# -------------------------------

DATA_DIR := /home/tsargsya/data

MARIADB_DIR := $(DATA_DIR)/mariadb
WORDPRESS_DIR := $(DATA_DIR)/wordpress

# -------------------------------
# Setup scripts
# -------------------------------

DOMAIN_SCRIPT := ./srcs/tools/configure_domain.sh
CERTIFICATE_SCRIPT := ./srcs/tools/generate_certificates.sh

# -------------------------------
# Color codes
# -------------------------------

RESET := \033[0m
BOLD := \033[1m
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
CYAN := \033[36m

# **************************************************************************** #
#                                  Build Rules                                 #
# **************************************************************************** #

all:
	@printf "$(BOLD)Inception build$(RESET)\n"
	@$(MAKE) --no-print-directory prepare
	@printf "$(YELLOW)[BUILD]$(RESET) Building and starting containers\n"
	@$(COMPOSE) up --build -d
	@printf "$(GREEN)[DONE]$(RESET) $(BOLD)$(NAME)$(RESET) is ready\n"

prepare:
	@printf "$(CYAN)[PREPARE]$(RESET) Creating data directories\n"
	@mkdir -p $(MARIADB_DIR)
	@mkdir -p $(WORDPRESS_DIR)
	@printf "$(CYAN)[PREPARE]$(RESET) Configuring domain\n"
	@$(DOMAIN_SCRIPT)
	@printf "$(CYAN)[PREPARE]$(RESET) Generating certificates\n"
	@$(CERTIFICATE_SCRIPT)

down:
	@printf "$(YELLOW)[DOWN]$(RESET) Stopping containers\n"
	@$(COMPOSE) down

clean:
	@printf "$(RED)[CLEAN]$(RESET) Stopping containers and removing orphans\n"
	@$(COMPOSE) down --remove-orphans

fclean:
	@printf "$(RED)[FCLEAN]$(RESET) Removing containers, images and volumes\n"
	@$(COMPOSE) down --rmi all --volumes --remove-orphans
	@printf "$(RED)[FCLEAN]$(RESET) Removing persistent data\n"
	@sudo rm -rf $(DATA_DIR)

re: fclean
	@$(MAKE) --no-print-directory all

rebuild:
	@printf "$(YELLOW)[REBUILD]$(RESET) Rebuilding without cache\n"
	@$(COMPOSE) down
	@$(MAKE) --no-print-directory prepare
	@$(COMPOSE) build --no-cache
	@$(COMPOSE) up -d
	@printf "$(GREEN)[DONE]$(RESET) $(BOLD)$(NAME)$(RESET) rebuilt\n"

.PHONY: all prepare down clean fclean re rebuild
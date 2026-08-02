*This project has been created as part of the 42 curriculum by tsargsya.*

# Inception

## Description

Inception is a system-administration project built around Docker. It creates a small, reproducible web infrastructure inside a virtual machine by building custom Docker images and orchestrating them with Docker Compose.

The stack contains three independent services:

- **NGINX** is the only public entrypoint. It accepts HTTPS connections on port `443` and allows TLS 1.2 and TLS 1.3 only.
- **WordPress with PHP-FPM** serves the website and listens internally on port `9000`.
- **MariaDB** stores the WordPress database and listens internally on port `3306`.

The images are built from `debian:bookworm`. Ready-made NGINX, WordPress, and MariaDB service images are not used.

## Architecture

```text
Browser
   |
   | HTTPS :443
   v
NGINX
   |
   | FastCGI :9000
   v
WordPress + PHP-FPM
   |
   | MariaDB protocol :3306
   v
MariaDB
```

All three containers are attached to the private `inception` bridge network. Docker DNS allows the services to reach one another by service name:

- NGINX connects to `wordpress:9000`;
- WordPress connects to `mariadb:3306`.

Only NGINX publishes a host port. MariaDB and PHP-FPM remain available only inside the Docker network.

## Project structure

```text
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── certificates/
├── docs/
│   ├── mandatory-testing.md
│   ├── mariadb.md
│   ├── nginx.md
│   └── wordpress.md
├── secrets/
├── tools/
│   ├── configure_domain.sh
│   ├── generate_certificates.sh
│   └── generate_secrets.py
└── srcs/
    ├── .env
    ├── docker-compose.yml
    ├── environment/
    │   ├── database.env
    │   └── wordpress.env
    └── requirements/
        ├── mariadb/
        ├── nginx/
        └── wordpress/
```

Each service directory contains its own Dockerfile, configuration files, and entrypoint script.

## Main design choices

### Custom images

Each service is built from its own Dockerfile. The real service process is launched in the foreground and becomes PID 1 through `exec`:

- `mariadbd --user=mysql`;
- `php-fpm8.2 -F`;
- `nginx -g 'daemon off;'`.

No `tail -f`, `sleep infinity`, `while true`, or similar process-keeping workaround is used.

### Persistent storage

The project declares two Docker named volumes:

- `mariadb_data` for `/var/lib/mysql`;
- `wordpress_data` for `/var/www/html`.

The volumes use Docker's local volume driver and store their data on the host in:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/wordpress
```

The services mount named volumes, rather than direct host bind mounts, for WordPress and MariaDB persistence.

### Secrets and configuration

Non-confidential configuration is stored in environment files:

- `srcs/.env`;
- `srcs/environment/database.env`;
- `srcs/environment/wordpress.env`.

Confidential values are stored in local secret files under `secrets/` and mounted by Docker under `/run/secrets/` inside the required containers. Secret files and the private TLS key are excluded from Git.

### TLS and local domain

The project uses the local domain:

```text
tsargsya.42.fr
```

`tools/configure_domain.sh` maps the domain to `127.0.0.1` in `/etc/hosts`. `tools/generate_certificates.sh` creates a self-signed certificate and private key for the domain. NGINX accepts TLS 1.2 and TLS 1.3 only.

## Technical comparisons

### Virtual machines vs Docker

A virtual machine emulates a complete computer and runs its own operating-system kernel. It provides strong isolation but uses more memory, storage, and startup time.

A Docker container isolates an application and its dependencies while sharing the host kernel. Containers are lighter and faster to create, but they are not virtual machines. In this project, the VM provides the required host environment, while Docker isolates the individual services inside that VM.

### Secrets vs environment variables

Environment variables are convenient for ordinary configuration such as a domain name, database name, hostname, or port. They are easy to inspect through process and container metadata, so they should not be used for passwords in this project.

Docker secrets expose confidential values as files under `/run/secrets/` only to the services that declare them. This reduces accidental disclosure through image layers and environment inspection. The local source files must still be protected and excluded from Git.

### Docker network vs host network

A Docker bridge network gives the project an isolated network namespace and built-in DNS based on service names. Only explicitly published ports become reachable from the host.

Host networking removes this isolation and makes a container use the host network stack directly. It also makes port ownership and service separation less explicit. This project uses a dedicated bridge network; host networking, legacy links, and `--link` are not used.

### Docker volumes vs bind mounts

A Docker volume is managed through Docker and is referenced by a volume name. It has a lifecycle independent from an individual container and is suitable for persistent application data.

A bind mount maps an arbitrary host path directly into a container. It gives precise host-path control but couples the container more tightly to the host filesystem layout and permissions.

The WordPress and MariaDB services use named volumes. The local volume driver places their data under `/home/tsargsya/data`, as required by the project. The generated TLS certificate and key are separate configuration artifacts and are mounted read-only into NGINX.

## Instructions

### Prerequisites

Run the project inside a Linux virtual machine with the following tools installed:

- Docker Engine;
- Docker Compose;
- GNU Make;
- Python 3;
- OpenSSL;
- `sudo` access.

The Docker daemon must be running and the current user must be allowed to execute Docker commands.

### Configuration

The committed environment files contain the non-secret project configuration:

```text
srcs/.env
srcs/environment/database.env
srcs/environment/wordpress.env
```

The default values configure:

```text
DOMAIN_NAME=tsargsya.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MARIADB_PORT=3306
MYSQL_HOST=mariadb
WP_TITLE=Inception
WP_ADMIN_USER=tsargsya
WP_USER=writer
```

Do not add passwords to these files.

### Generate local secrets

Create the required secret files before the first launch:

```bash
python3 tools/generate_secrets.py
```

The script creates:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Existing non-empty secret files are preserved. To enter passwords manually instead of generating them automatically, run:

```bash
python3 tools/generate_secrets.py --manual
```

The generated files receive permission mode `600`.

### Build and start

From the repository root, run:

```bash
make
```

The default target:

1. creates the host data directories;
2. configures `tsargsya.42.fr` in `/etc/hosts`;
3. generates or validates the TLS certificate;
4. builds the three custom images;
5. creates the network and named volumes;
6. starts the complete stack in detached mode.

Check the containers:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Open the website at:

```text
https://tsargsya.42.fr
```

Open the WordPress administration panel at:

```text
https://tsargsya.42.fr/wp-admin
```

The certificate is self-signed, so a browser may display a local certificate warning.

### Stop and clean

Stop and remove the containers while preserving persistent data:

```bash
make down
```

Remove containers and orphaned project containers while preserving the host data directories:

```bash
make clean
```

Remove containers, project images, Docker volume objects, and all data under `/home/tsargsya/data`:

```bash
make fclean
```

Rebuild everything from a clean data state:

```bash
make re
```

`make fclean` is destructive. It removes the WordPress website files and MariaDB database data. It does not remove local secret files or generated certificate files.

## Persistence and restart behavior

All containers use `restart: on-failure`. Docker restarts a container when its main process exits with an error.

Persistent data survives `make down` and container recreation because it is stored outside the writable container layers. It does not survive `make fclean`, because that target intentionally removes `/home/tsargsya/data`.

## MariaDB initialization recovery

MariaDB has two separate initialization states:

1. `/var/lib/mysql/mysql` indicates that MariaDB system tables exist.
2. `/var/lib/mysql/.inception_initialized` indicates that the project-specific SQL initialization completed successfully.

The checks are intentionally independent. A container can stop after `mariadb-install-db` creates the system tables but before the WordPress database, application user, privileges, and root password are fully configured. Checking only for the `mysql` directory would incorrectly treat that partially initialized volume as complete.

When system tables are missing, the entrypoint creates them with `mariadb-install-db`. When the project marker is missing, it starts a temporary local MariaDB server and runs idempotent SQL initialization. The marker is created only after the SQL command completes and the temporary server shuts down successfully.

This makes a failed cold start recoverable without immediately deleting the persistent volume or rebuilding the image.

## Testing and troubleshooting

The repository contains focused troubleshooting guides:

- [MariaDB troubleshooting](docs/mariadb.md)
- [WordPress troubleshooting](docs/wordpress.md)
- [NGINX troubleshooting](docs/nginx.md)

A complete mandatory-part acceptance procedure is available in:

- [Mandatory full test guide](docs/mandatory-testing.md)

Useful first checks are:

```bash
docker compose -f srcs/docker-compose.yml ps -a
docker compose -f srcs/docker-compose.yml logs --tail=100 mariadb
docker compose -f srcs/docker-compose.yml logs --tail=100 wordpress
docker compose -f srcs/docker-compose.yml logs --tail=100 nginx
```

## Security notes

- Never commit files from `secrets/`.
- Never commit `certificates/inception.key`.
- Never place passwords in a Dockerfile or tracked environment file.
- Do not print secret values into logs, screenshots, or documentation.
- Do not use the `latest` image tag.
- Keep secret and private-key file permissions restricted.

## Resources

The following references were used while implementing and reviewing the project:

- [Docker documentation](https://docs.docker.com/)
- [Docker Compose documentation](https://docs.docker.com/compose/)
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Docker storage documentation](https://docs.docker.com/engine/storage/)
- [Docker networking documentation](https://docs.docker.com/engine/network/)
- [NGINX documentation](https://nginx.org/en/docs/)
- [MariaDB Server documentation](https://mariadb.com/docs/server/)
- [PHP-FPM documentation](https://www.php.net/manual/en/install.fpm.php)
- [WordPress developer documentation](https://developer.wordpress.org/)
- [WP-CLI documentation](https://wp-cli.org/)
- [OpenSSL documentation](https://docs.openssl.org/)

### Use of AI

AI was used as a learning and review assistant during the project. It helped to:

- explain Docker, networking, volumes, PID 1, NGINX, PHP-FPM, WordPress, and MariaDB concepts;
- discuss implementation alternatives before changes were made;
- analyze logs and error messages during troubleshooting;
- propose test cases for cold starts, persistence, restart behavior, TLS, networking, and secret handling;
- review shell scripts, configuration files, and documentation for clarity and consistency.

All generated suggestions were reviewed against the project requirements, tested in the virtual machine, and adjusted to match the final implementation. The project author remains responsible for the code, configuration, tests, and documentation.

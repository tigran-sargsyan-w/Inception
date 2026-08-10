*This project has been created as part of the 42 curriculum by tsargsya.*

# Inception

## Description

Inception is a system-administration project built around Docker. It creates a reproducible multi-service web infrastructure inside a Linux virtual machine. Every service runs in its own container, is built from a custom Dockerfile based on `debian:bookworm`, and is orchestrated with Docker Compose.

The mandatory stack contains:

- **NGINX** — the HTTPS reverse proxy and main public entrypoint on port `443`, with TLS 1.2 and TLS 1.3 only.
- **WordPress + PHP-FPM** — the website application, listening internally on port `9000`.
- **MariaDB** — the WordPress database, listening internally on port `3306`.
- **Two named volumes** — one for MariaDB data and one for WordPress files.
- **A private Docker bridge network** — used for service-to-service communication.

The project also implements all requested bonus services:

- **Redis** — object cache used by WordPress.
- **FTP server** — provides FTP access to the WordPress volume.
- **Static website** — a separate portfolio site, implemented without PHP.
- **Adminer** — browser-based database administration.
- **Dockpeek** — the service of choice, used to inspect Docker containers and logs through a web interface.

Ready-made service images are not used for the project services. Each service is built from its own Dockerfile.

## Architecture

```text
                                  HTTPS :443
                                     |
                                     v
                                  +-------+
                                  | NGINX |
                                  +-------+
                         _________/   |   \__________
                        /             |              \
                       v              v               v
                WordPress:9000   Adminer:9000   Static site:8080
                    |   \                              
                    |    \ Redis:6379                  Dockpeek:8000
                    v
                MariaDB:3306

Host-published bonus ports:
FTP :21 and passive range :21000-21010
```

All containers join the private `inception` Docker bridge network. Docker DNS allows services to reach each other by service name.

NGINX serves four HTTPS virtual hosts:

```text
https://tsargsya.42.fr
https://adminer.tsargsya.42.fr
https://portfolio.tsargsya.42.fr
https://dockpeek.tsargsya.42.fr
```

The FTP service is the only bonus service that publishes additional host ports directly, because the FTP protocol requires its control port and passive data-port range.

## Project structure

```text
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── certificates/
├── docs/
│   ├── adminer.md
│   ├── dockpeek.md
│   ├── ftp.md
│   ├── mandatory-testing.md
│   ├── mariadb.md
│   ├── nginx.md
│   ├── redis.md
│   ├── static_site.md
│   └── wordpress.md
├── secrets/
├── tools/
│   └── test_mandatory.sh
└── srcs/
    ├── .env
    ├── docker-compose.yml
    ├── environment/
    │   ├── database.env
    │   ├── dockpeek.env
    │   ├── ftp.env
    │   └── wordpress.env
    ├── tools/
    │   ├── configure_domain.sh
    │   ├── generate_certificates.sh
    │   └── generate_secrets.py
    └── requirements/
        ├── adminer/
        ├── dockpeek/
        ├── ftp/
        ├── mariadb/
        ├── nginx/
        ├── redis/
        ├── static_site/
        └── wordpress/
```

Each service directory contains its own Dockerfile and, where required, configuration and entrypoint files.

## Main design choices

### Custom images and PID 1

Every service is built from a custom Dockerfile. Long-running services are started in the foreground and entrypoint scripts finish with `exec` so that the real application process becomes PID 1.

No `tail -f`, `sleep infinity`, `while true`, or similar container-keeping workaround is used.

### Persistent storage

The project declares two Docker named volumes:

- `mariadb_data` mounted at `/var/lib/mysql`;
- `wordpress_data` mounted at `/var/www/html`.

They use Docker's local volume driver and store their data on the host under:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/wordpress
```

The FTP container mounts `wordpress_data`, which lets the FTP user work with the same WordPress files used by the website.

### Secrets and configuration

Non-confidential configuration is stored in tracked environment files:

```text
srcs/.env
srcs/environment/database.env
srcs/environment/wordpress.env
srcs/environment/ftp.env
srcs/environment/dockpeek.env
```

Confidential values are stored locally under `secrets/` and mounted by Docker as files under `/run/secrets/` only into services that need them.

Current secret files are:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
secrets/ftp_password.txt
secrets/dockpeek_password.txt
secrets/dockpeek_secret_key.txt
```

Secret files and the private TLS key are excluded from Git.

### Redis cache

Redis runs in a dedicated container on internal port `6379`. WordPress includes the PHP Redis extension and Redis tools and connects to the `redis` service through the Docker network. Redis is not published to the host.

### HTTPS routing for bonus web services

Adminer, the static website, and Dockpeek do not publish their application ports to the host. NGINX reverse-proxies them using separate local domains over the same HTTPS port `443`.

This keeps NGINX as the HTTPS entrypoint while still exposing the bonus web interfaces cleanly.

### Dockpeek as the service of choice

Dockpeek was selected because it is directly useful for a Docker-focused system-administration project. It provides a web interface for inspecting containers and logs, making the state of the infrastructure easier to observe during development and evaluation.

The Docker socket is mounted read-only into the Dockpeek container. Dockpeek itself is exposed internally on port `8000` and is reached through NGINX at `https://dockpeek.tsargsya.42.fr`.

## Technical comparisons

### Virtual Machines vs Docker

A virtual machine emulates a complete computer and runs its own operating-system kernel. It provides strong isolation but requires more memory, storage, and startup time.

A Docker container isolates an application and its dependencies while sharing the host kernel. Containers are lighter and faster to recreate. In this project, the VM provides the required host environment and Docker isolates the individual services inside that VM.

### Secrets vs Environment Variables

Environment variables are appropriate for ordinary configuration such as domains, database names, usernames, ports, and service hostnames.

Passwords and secret keys are more sensitive. This project stores them in local secret files and exposes them inside selected containers under `/run/secrets/`, rather than putting them in Dockerfiles or tracked environment files.

### Docker Network vs Host Network

A Docker bridge network gives the stack an isolated network and built-in DNS using service names. Only explicitly published ports are reachable from the host.

Host networking removes this isolation and makes services share the host network stack directly. This project uses a dedicated bridge network; host networking, Compose `links`, and `--link` are not used.

### Docker Volumes vs Bind Mounts

A Docker volume is managed as a Docker resource and has a lifecycle independent from an individual container. It is suitable for persistent application data.

A bind mount maps a host path directly into a container and couples the container more closely to the host filesystem layout.

The MariaDB and WordPress persistent stores are Docker named volumes. The local volume driver places their data under `/home/tsargsya/data`, as required by the project. Configuration artifacts such as the generated TLS certificate/key and the read-only Docker socket used by Dockpeek are separate mounts, not application-data volumes.

## Instructions

### Prerequisites

Run the project inside a Linux virtual machine with:

- Docker Engine;
- Docker Compose;
- GNU Make;
- Python 3;
- OpenSSL;
- `sudo` access.

The Docker daemon must be running and the current user must be allowed to execute Docker commands.

### Generate local secrets

Before the first launch, run:

```bash
python3 srcs/tools/generate_secrets.py
```

The script creates all required MariaDB, WordPress, FTP, and Dockpeek secret files. Existing non-empty secret files are preserved.

For interactive password entry:

```bash
python3 srcs/tools/generate_secrets.py --manual
```

New secret files are created with permission mode `600`.

### Build and start

From the repository root:

```bash
make
```

The default target:

1. creates the persistent-data directories;
2. configures the local project domains in `/etc/hosts`;
3. generates or validates the TLS certificate;
4. builds the custom images;
5. creates the Docker network and named volumes;
6. starts the complete stack in detached mode.

Check the stack:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected services:

```text
mariadb
wordpress
nginx
adminer
static_site
redis
ftp
dockpeek
```

### Access the services

WordPress:

```text
https://tsargsya.42.fr
```

WordPress administration:

```text
https://tsargsya.42.fr/wp-admin
```

Adminer:

```text
https://adminer.tsargsya.42.fr
```

Static portfolio:

```text
https://portfolio.tsargsya.42.fr
```

Dockpeek:

```text
https://dockpeek.tsargsya.42.fr
```

FTP:

```text
Host: 127.0.0.1
Port: 21
User: ftpuser
Password: secrets/ftp_password.txt
Passive ports: 21000-21010
```

The HTTPS certificate is self-signed, so a browser may display a local certificate warning.

### Stop and clean

Stop containers while preserving persistent data:

```bash
make down
```

Remove containers and orphaned project containers while preserving persistent host data:

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

Force a no-cache image rebuild without deleting persistent data first:

```bash
make rebuild
```

`make fclean` and therefore `make re` are destructive for the WordPress and MariaDB persistent data. They do not remove the local secret files or generated certificate files.

## Persistence and restart behavior

All services use `restart: on-failure`.

Persistent MariaDB and WordPress data survive `make down` and container recreation because the data is stored outside the writable container layers. It does not survive `make fclean`, which intentionally removes `/home/tsargsya/data`.

## Testing and troubleshooting

The repository contains focused guides for the mandatory and bonus services:

- [Mandatory full test guide](docs/mandatory-testing.md)
- [MariaDB](docs/mariadb.md)
- [WordPress](docs/wordpress.md)
- [NGINX](docs/nginx.md)
- [Redis](docs/redis.md)
- [FTP](docs/ftp.md)
- [Adminer](docs/adminer.md)
- [Static website](docs/static_site.md)
- [Dockpeek](docs/dockpeek.md)

Useful first checks are:

```bash
docker compose -f srcs/docker-compose.yml ps -a
docker compose -f srcs/docker-compose.yml logs --tail=100
```

## Security notes

- Never commit files from `secrets/`.
- Never commit `certificates/inception.key`.
- Never place passwords or secret keys in Dockerfiles or tracked environment files.
- Do not print secret values into logs, screenshots, or documentation.
- Do not use the `latest` image tag.
- Keep secret and private-key permissions restricted.
- The Docker socket grants powerful access to the Docker daemon even when mounted read-only at the filesystem level; access to Dockpeek must therefore be treated as privileged infrastructure access.

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
- [Redis documentation](https://redis.io/docs/)
- [Adminer](https://www.adminer.org/)
- [Dockpeek](https://github.com/dockpeek/dockpeek)
- [OpenSSL documentation](https://docs.openssl.org/)

### Use of AI

AI was used as a learning and review assistant during both the mandatory and bonus parts of the project. It helped to:

- explain Docker, networking, volumes, PID 1, TLS, NGINX, PHP-FPM, WordPress, MariaDB, Redis, FTP, reverse proxies, and container-observability concepts;
- discuss implementation alternatives before changes were made;
- analyze logs and error messages during troubleshooting;
- propose tests for cold starts, persistence, restart behavior, TLS, networking, caching, FTP access, bonus web services, and secret handling;
- review shell scripts, Dockerfiles, configuration files, and documentation for clarity and consistency.

All suggestions were reviewed against the project requirements, tested in the virtual machine, and adjusted to match the final implementation. The project author remains responsible for the code, configuration, tests, and documentation.

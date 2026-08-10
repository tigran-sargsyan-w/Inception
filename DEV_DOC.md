# Inception Developer Documentation

## Purpose

This document describes how to prepare, build, run, inspect, and maintain the complete Inception project from a developer perspective, including the bonus services.

The stack contains eight custom Docker images:

```text
mariadb:inception
wordpress:inception
nginx:inception
adminer:inception
static_site:inception
redis:inception
ftp:inception
dockpeek:inception
```

Every service runs in its own container and is built from a project Dockerfile based on `debian:bookworm`.

## Architecture

```text
Host / Linux VM
└── Docker bridge network: inception
    ├── nginx
    │   ├── publishes host port 443
    │   ├── mounts wordpress_data read-only
    │   ├── forwards WordPress PHP requests to wordpress:9000
    │   ├── proxies Adminer to adminer:9000
    │   ├── proxies the static site to static_site:8080
    │   └── proxies Dockpeek to dockpeek:8000
    │
    ├── wordpress
    │   ├── runs PHP-FPM on 9000
    │   ├── mounts wordpress_data at /var/www/html
    │   ├── connects to mariadb:3306
    │   └── uses redis:6379 for object caching
    │
    ├── mariadb
    │   ├── runs MariaDB on 3306
    │   └── mounts mariadb_data at /var/lib/mysql
    │
    ├── redis
    │   └── runs Redis on 6379
    │
    ├── adminer
    │   └── serves Adminer internally on 9000
    │
    ├── static_site
    │   └── serves the portfolio internally on 8080
    │
    ├── ftp
    │   ├── publishes host port 21
    │   ├── publishes passive ports 21000-21010
    │   └── mounts wordpress_data at /var/www/html
    │
    └── dockpeek
        ├── serves internally on 8000
        └── mounts /var/run/docker.sock read-only
```

All services join the same private bridge network. Only NGINX and FTP publish host ports.

## Repository layout

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

Each service directory contains its Dockerfile and any configuration, application files, or entrypoint scripts required by that service.

## Prerequisites

Use a Linux virtual machine with:

- Docker Engine;
- Docker Compose;
- GNU Make;
- Python 3;
- OpenSSL;
- `curl` for verification;
- `sudo` access for `/etc/hosts` and destructive host-data cleanup.

Check the environment:

```bash
docker --version
docker compose version
make --version | head -n 1
python3 --version
openssl version
curl --version | head -n 1
sudo -v
docker info >/dev/null && echo 'Docker daemon: OK'
```

## Configuration files

### Local domains

`srcs/.env` contains the HTTPS virtual-host names:

```text
DOMAIN_NAME=tsargsya.42.fr
ADMINER_DOMAIN=adminer.tsargsya.42.fr
STATIC_SITE_DOMAIN=portfolio.tsargsya.42.fr
DOCKPEEK_DOMAIN=dockpeek.tsargsya.42.fr
```

`srcs/tools/configure_domain.sh` reads these values and ensures that each domain points to `127.0.0.1` in `/etc/hosts`.

The script refuses to continue if one of these names already maps to another IP address.

### Database configuration

`srcs/environment/database.env` stores non-secret MariaDB settings such as:

```text
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MARIADB_PORT=3306
```

### WordPress configuration

`srcs/environment/wordpress.env` stores non-secret WordPress settings, including the MariaDB hostname, WordPress title, administrator account name, and second user.

The administrator username must not contain `admin` in any letter case.

### FTP configuration

`srcs/environment/ftp.env` contains:

```text
FTP_USER=ftpuser
FTP_PORT=21
FTP_PASV_ADDRESS=127.0.0.1
FTP_PASV_MIN_PORT=21000
FTP_PASV_MAX_PORT=21010
```

The FTP password is not stored in this file; it is provided through a Docker secret.

### Dockpeek configuration

`srcs/environment/dockpeek.env` contains:

```text
USERNAME=dockpeek
TRUST_PROXY_HEADERS=true
TRUSTED_PROXY_COUNT=1
```

The Dockpeek password and application secret key are supplied through Docker secrets.

## Secret setup

The Compose file declares seven secrets:

```text
db_root_password
db_password
wp_admin_password
wp_user_password
ftp_password
dockpeek_password
dockpeek_secret_key
```

Their local source files are:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
secrets/ftp_password.txt
secrets/dockpeek_password.txt
secrets/dockpeek_secret_key.txt
```

Generate them automatically:

```bash
python3 srcs/tools/generate_secrets.py
```

Generate them interactively:

```bash
python3 srcs/tools/generate_secrets.py --manual
```

The generator:

- creates 32-character secrets by default;
- ensures generated passwords contain enabled uppercase, lowercase, digit, and special-character groups;
- preserves existing non-empty files;
- recreates empty secret files;
- assigns mode `600` to new files;
- never prints generated values.

Inside containers, declared secrets are available as files under `/run/secrets/`.

## TLS setup

The project generates a self-signed certificate and private key under:

```text
certificates/inception.crt
certificates/inception.key
```

NGINX mounts them read-only and accepts TLS 1.2 and TLS 1.3 only.

The same HTTPS endpoint is used for the WordPress, Adminer, static-site, and Dockpeek domains through separate NGINX `server` blocks.

## Build and launch

From the repository root:

```bash
make
```

The default `all` target depends on `prepare` and then runs:

```bash
docker compose -f srcs/docker-compose.yml up --build -d
```

The preparation stage:

1. creates `/home/tsargsya/data/mariadb`;
2. creates `/home/tsargsya/data/wordpress`;
3. configures all local project domains;
4. generates or validates the TLS certificate.

Validate Compose before starting:

```bash
docker compose -f srcs/docker-compose.yml config
```

List resolved resources:

```bash
docker compose -f srcs/docker-compose.yml config --services
docker compose -f srcs/docker-compose.yml config --images
docker compose -f srcs/docker-compose.yml config --volumes
docker compose -f srcs/docker-compose.yml config --networks
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

Expected named volumes:

```text
mariadb_data
wordpress_data
```

Expected network:

```text
inception
```

## Makefile lifecycle

### Start or update

```bash
make
```

Builds changed images and starts the stack.

### Stop while preserving data

```bash
make down
```

Equivalent to:

```bash
docker compose -f srcs/docker-compose.yml down
```

### Remove orphaned containers

```bash
make clean
```

Equivalent to a Compose shutdown with `--remove-orphans`. Persistent host data remains.

### Full destructive cleanup

```bash
make fclean
```

This removes project containers, project images, Docker volume objects, the project network, and:

```text
/home/tsargsya/data
```

It does not remove the local secret files or generated TLS files.

### Full clean rebuild

```bash
make re
```

Runs `fclean` and then `all`.

### No-cache image rebuild without deleting persistent data

```bash
make rebuild
```

This runs a Compose shutdown, prepares the environment, rebuilds all images with `--no-cache`, and starts the containers again.

## Docker Compose management commands

Show service state:

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

Build without starting:

```bash
docker compose -f srcs/docker-compose.yml build
```

Build one service:

```bash
docker compose -f srcs/docker-compose.yml build redis
docker compose -f srcs/docker-compose.yml build ftp
docker compose -f srcs/docker-compose.yml build adminer
docker compose -f srcs/docker-compose.yml build static_site
docker compose -f srcs/docker-compose.yml build dockpeek
```

Recreate one service:

```bash
docker compose -f srcs/docker-compose.yml up -d --no-deps --build SERVICE_NAME
```

Show logs:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=100
docker compose -f srcs/docker-compose.yml logs -f SERVICE_NAME
```

Open a shell:

```bash
docker exec -it SERVICE_NAME sh
```

Run WP-CLI as the WordPress filesystem owner:

```bash
docker exec -it -u www-data wordpress wp --path=/var/www/html --info
```

Inspect resources:

```bash
docker image ls
docker volume ls
docker network ls
docker inspect mariadb
docker inspect wordpress
docker inspect nginx
docker inspect redis
docker inspect ftp
docker inspect adminer
docker inspect static_site
docker inspect dockpeek
```

## Mandatory service implementation

### MariaDB

MariaDB listens internally on `3306` and persists its data in `mariadb_data` at `/var/lib/mysql`.

Its entrypoint separates MariaDB system-table initialization from project SQL initialization. A project marker is created only after the project-specific initialization succeeds, which makes interrupted cold starts recoverable.

The real MariaDB server is started through `exec`, making it PID 1.

### WordPress and PHP-FPM

WordPress listens internally through PHP-FPM on `9000` and mounts `wordpress_data` at `/var/www/html`.

The image installs WP-CLI, the required PHP extensions, `php-redis`, and Redis tools.

The entrypoint initializes WordPress only when necessary, waits for MariaDB, creates the expected users, configures WordPress, and finally starts PHP-FPM in the foreground.

### NGINX

NGINX is the main HTTPS entrypoint on host port `443`.

The generated configuration:

- enables TLS 1.2 and TLS 1.3 only;
- serves WordPress and forwards PHP requests to `wordpress:9000`;
- reverse-proxies Adminer to `adminer:9000`;
- reverse-proxies the static site to `static_site:8080`;
- reverse-proxies Dockpeek to `dockpeek:8000`.

The main NGINX process runs in the foreground.

## Bonus service implementation

### Redis

Redis runs in a dedicated container using:

```text
redis-server /etc/redis/redis.conf
```

It listens internally on port `6379` and is not published to the host.

WordPress depends on the Redis service and includes both the PHP Redis extension and Redis command-line tools. The cache therefore remains isolated inside the Docker network.

Quick check:

```bash
docker exec redis redis-cli ping
```

Expected:

```text
PONG
```

For deeper Redis checks, see `docs/redis.md`.

### FTP

The FTP service mounts:

```text
wordpress_data:/var/www/html
```

This means FTP operates on the same persistent files used by WordPress.

Published ports are:

```text
21:21
21000-21010:21000-21010
```

The username and passive-mode configuration come from `srcs/environment/ftp.env`; the password comes from `secrets/ftp_password.txt` through Docker secrets.

For detailed tests, see `docs/ftp.md`.

### Static website

The static website runs in its own container and listens internally on `8080`.

NGINX exposes it through:

```text
https://portfolio.tsargsya.42.fr
```

No PHP is used for this service.

For implementation and testing details, see `docs/static_site.md`.

### Adminer

Adminer runs in its own container and connects to MariaDB through the private Docker network.

Its application port remains internal. NGINX exposes the interface through:

```text
https://adminer.tsargsya.42.fr
```

For detailed checks, see `docs/adminer.md`.

### Dockpeek — service of choice

Dockpeek is the additional service selected for the free-choice bonus requirement.

It is useful in this project because it provides a web interface for observing Docker containers and logs, which directly complements the system-administration and container-orchestration goals of Inception.

The image downloads Dockpeek version `v1.7.2`, installs its Python dependencies in a virtual environment, and starts the application with Gunicorn on internal port `8000`.

Compose mounts:

```text
/var/run/docker.sock:/var/run/docker.sock:ro
```

The filesystem mount is read-only, but the Docker socket itself represents privileged access to the Docker daemon. This service therefore must be treated as an administrative interface.

Dockpeek is reverse-proxied by NGINX at:

```text
https://dockpeek.tsargsya.42.fr
```

Its username is configured in `srcs/environment/dockpeek.env`; its password and application secret key are supplied using Docker secrets.

For implementation and testing details, see `docs/dockpeek.md`.

## Network and DNS

All eight services join the `inception` bridge network.

Useful DNS checks:

```bash
docker exec nginx getent hosts wordpress
docker exec wordpress getent hosts mariadb
docker exec wordpress getent hosts redis
docker exec nginx getent hosts adminer
docker exec nginx getent hosts static_site
docker exec nginx getent hosts dockpeek
```

Inspect the network:

```bash
docker network inspect inception_inception
```

The exact Docker network object name may include the Compose project name.

Host networking, Compose `links`, and `--link` are not used.

## Ports

Expected host-published ports:

```text
nginx   443/tcp
ftp     21/tcp
ftp     21000-21010/tcp
```

Internal-only service ports:

```text
mariadb      3306
wordpress    9000
redis        6379
adminer      9000
static_site  8080
dockpeek     8000
```

Inspect published ports:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Inspect host listeners:

```bash
sudo ss -lntp | grep -E ':(21|443|3306|6379|8000|8080|9000|2100[0-9]|21010)\b' || true
```

## Volumes and persistence

The Compose file declares two named volumes:

```text
mariadb_data
wordpress_data
```

They use the local driver with host-backed storage:

```text
mariadb_data   -> /home/tsargsya/data/mariadb
wordpress_data -> /home/tsargsya/data/wordpress
```

Container mount points are:

```text
mariadb_data   -> /var/lib/mysql
wordpress_data -> /var/www/html
```

NGINX mounts `wordpress_data` read-only. FTP mounts the same WordPress volume read-write.

Inspect volumes:

```bash
docker volume inspect mariadb_data
docker volume inspect wordpress_data
```

Persistence should be tested with `make down`, not `make fclean`:

1. create identifiable WordPress content;
2. run `make down`;
3. run `make`;
4. verify that the content still exists.

## Process and restart checks

All services use:

```text
restart: on-failure
```

Display PID 1 in each container:

```bash
for container in mariadb wordpress nginx adminer static_site redis ftp dockpeek
do
    echo "===== $container ====="
    docker exec "$container" sh -c \
        'tr "\000" " " </proc/1/cmdline; echo'
done
```

Check restart policy and restart counters:

```bash
for container in mariadb wordpress nginx adminer static_site redis ftp dockpeek
do
    docker inspect \
        --format '{{.Name}} policy={{.HostConfig.RestartPolicy.Name}} restart_count={{.RestartCount}} status={{.State.Status}}' \
        "$container"
done
```

## HTTPS verification

Check the virtual hosts:

```bash
curl -k -sS -o /dev/null -w 'WordPress: %{http_code}\n' https://tsargsya.42.fr/
curl -k -sS -o /dev/null -w 'Adminer: %{http_code}\n' https://adminer.tsargsya.42.fr/
curl -k -sS -o /dev/null -w 'Portfolio: %{http_code}\n' https://portfolio.tsargsya.42.fr/
curl -k -sS -o /dev/null -w 'Dockpeek: %{http_code}\n' https://dockpeek.tsargsya.42.fr/
```

Check TLS 1.2 and TLS 1.3:

```bash
openssl s_client -connect tsargsya.42.fr:443 -servername tsargsya.42.fr -tls1_2 </dev/null
openssl s_client -connect tsargsya.42.fr:443 -servername tsargsya.42.fr -tls1_3 </dev/null
```

TLS 1.0 and TLS 1.1 must be rejected.

## Bonus verification checklist

### Redis

```bash
docker exec redis redis-cli ping
```

Then verify WordPress cache behavior using the procedure in `docs/redis.md`.

### FTP

```bash
docker compose -f srcs/docker-compose.yml ps ftp
```

Verify authentication, passive-mode connectivity, and read/write access to WordPress files using `docs/ftp.md`.

### Adminer

```bash
curl -k -I https://adminer.tsargsya.42.fr
```

Verify a database login through the browser using the MariaDB application account.

### Static site

```bash
curl -k -I https://portfolio.tsargsya.42.fr
```

Verify that it is served by its own container and does not rely on PHP.

### Dockpeek

```bash
curl -k -I https://dockpeek.tsargsya.42.fr
```

Log in and verify that container/log information is visible. See `docs/dockpeek.md` for service-specific checks and security considerations.

## Troubleshooting documentation

Detailed guides are available in:

```text
docs/mandatory-testing.md
docs/mariadb.md
docs/wordpress.md
docs/nginx.md
docs/redis.md
docs/ftp.md
docs/adminer.md
docs/static_site.md
docs/dockpeek.md
```

Useful first commands:

```bash
docker compose -f srcs/docker-compose.yml ps -a
docker compose -f srcs/docker-compose.yml logs --tail=100
docker compose -f srcs/docker-compose.yml config
```

## Security notes

- Never commit `secrets/*.txt`.
- Never commit the private TLS key.
- Keep passwords and secret keys out of Dockerfiles and tracked environment files.
- Do not print secret values to logs or documentation.
- Do not use the `latest` image tag.
- Keep secret/private-key permissions restricted.
- Do not expose MariaDB, PHP-FPM, Redis, Adminer, the static-site application port, or Dockpeek's application port directly to the host unless the project design explicitly requires it.
- Treat access to Dockpeek as privileged infrastructure access because it communicates with the Docker daemon through the mounted Docker socket.

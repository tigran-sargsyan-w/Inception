# Inception Developer Documentation

## Purpose

This document explains how to prepare, build, run, inspect, and maintain the Inception project from a developer perspective.

The stack is composed of three custom Docker images:

- `mariadb:inception`;
- `wordpress:inception`;
- `nginx:inception`.

Each image is built from `debian:bookworm`, and each service runs in its own container.

## Architecture

```text
Host / VM
└── Docker bridge network: inception
    ├── nginx
    │   ├── publishes host port 443
    │   ├── reads the WordPress volume read-only
    │   └── forwards PHP requests to wordpress:9000
    ├── wordpress
    │   ├── runs PHP-FPM on port 9000
    │   ├── mounts wordpress_data at /var/www/html
    │   └── connects to mariadb:3306
    └── mariadb
        ├── runs MariaDB on port 3306
        └── mounts mariadb_data at /var/lib/mysql
```

Only NGINX publishes a host port. WordPress and MariaDB use internal container ports on the project network.

## Repository layout

```text
.
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── certificates/
│   └── .gitkeep
├── docs/
│   ├── mandatory-testing.md
│   ├── mariadb.md
│   ├── nginx.md
│   └── wordpress.md
├── secrets/
│   └── .gitkeep
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
        │   ├── Dockerfile
        │   ├── conf/99-inception.cnf
        │   └── tools/
        │       ├── docker-entrypoint.sh
        │       └── init.sql.template
        ├── nginx/
        │   ├── Dockerfile
        │   ├── conf/default.conf.template
        │   └── tools/docker-entrypoint.sh
        └── wordpress/
            ├── Dockerfile
            ├── conf/www.conf
            └── tools/docker-entrypoint.sh
```

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

### Domain configuration

`srcs/.env` contains:

```text
DOMAIN_NAME=tsargsya.42.fr
```

The root Makefile calls `tools/configure_domain.sh`. The script reads `DOMAIN_NAME` and ensures that `/etc/hosts` contains:

```text
127.0.0.1    tsargsya.42.fr
```

It refuses to continue when the same domain already points to another address.

### Database configuration

`srcs/environment/database.env` contains non-secret MariaDB settings:

```text
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MARIADB_PORT=3306
```

### WordPress configuration

`srcs/environment/wordpress.env` contains:

```text
MYSQL_HOST=mariadb
WP_TITLE=Inception
WP_ADMIN_USER=tsargsya
WP_ADMIN_EMAIL=owner@tsargsya.42.fr
WP_USER=writer
WP_USER_EMAIL=writer@tsargsya.42.fr
```

The administrator username must not contain `admin` in any letter case.

Do not place passwords in tracked environment files.

## Secret setup

The Compose file declares four secrets:

```text
db_root_password
db_password
wp_admin_password
wp_user_password
```

Their local source files are:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Generate them automatically:

```bash
python3 tools/generate_secrets.py
```

Generate them interactively:

```bash
python3 tools/generate_secrets.py --manual
```

The script:

- creates 32-character passwords by default;
- preserves existing non-empty files;
- assigns mode `600` to newly created files;
- never prints the generated values.

Verify the files without displaying their contents:

```bash
for file in \
    secrets/db_root_password.txt \
    secrets/db_password.txt \
    secrets/wp_admin_password.txt \
    secrets/wp_user_password.txt
do
    if [ -s "$file" ]; then
        echo "OK: $file"
    else
        echo "MISSING OR EMPTY: $file"
    fi
done

stat -c '%a %U:%G %n' secrets/*.txt
```

The source files are ignored by Git. Inside containers, Docker mounts each declared secret as a file under `/run/secrets/`.

## TLS setup

`tools/generate_certificates.sh` creates:

```text
certificates/inception.crt
certificates/inception.key
```

The certificate is:

- self-signed;
- valid for 365 days;
- generated with a 2048-bit RSA key;
- issued for `tsargsya.42.fr`;
- created with a `subjectAltName` entry for the domain.

The script validates existing TLS files and reuses them when they are non-empty, unexpired, valid for the configured domain, and use a matching key pair.

File permissions are:

```text
certificate: 644
private key: 600
```

The files are mounted read-only into NGINX. The private key is ignored by Git.

## Build and launch

From the repository root:

```bash
make
```

The default `all` target depends on `prepare`, then executes:

```bash
docker compose -f srcs/docker-compose.yml up --build -d
```

The preparation stage:

1. creates `/home/tsargsya/data/mariadb`;
2. creates `/home/tsargsya/data/wordpress`;
3. runs `tools/configure_domain.sh`;
4. runs `tools/generate_certificates.sh`.

Validate Compose before starting:

```bash
docker compose -f srcs/docker-compose.yml config
```

List the resolved resources:

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
```

Expected images:

```text
mariadb:inception
wordpress:inception
nginx:inception
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

The containers and project network are removed. Host data under `/home/tsargsya/data` remains.

### Remove orphaned containers

```bash
make clean
```

Equivalent to a Compose shutdown with `--remove-orphans`. Persistent data remains.

### Full destructive cleanup

```bash
make fclean
```

This executes:

```bash
docker compose -f srcs/docker-compose.yml down \
    --rmi all \
    --volumes \
    --remove-orphans
sudo rm -rf /home/tsargsya/data
```

It removes project containers, images, volume objects, network, and persistent WordPress and MariaDB data.

It does not remove:

```text
secrets/*.txt
certificates/inception.crt
certificates/inception.key
```

### Full rebuild

```bash
make re
```

Runs `fclean`, then `all`.

## Docker Compose management commands

Show service state:

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

Build without starting:

```bash
docker compose -f srcs/docker-compose.yml build
```

Rebuild one service:

```bash
docker compose -f srcs/docker-compose.yml build mariadb
docker compose -f srcs/docker-compose.yml build wordpress
docker compose -f srcs/docker-compose.yml build nginx
```

Recreate one service after rebuilding:

```bash
docker compose -f srcs/docker-compose.yml up -d --no-deps --build nginx
```

Show logs:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=100
docker compose -f srcs/docker-compose.yml logs -f nginx
```

Open a shell in a running container:

```bash
docker exec -it mariadb sh
docker exec -it wordpress sh
docker exec -it nginx sh
```

Run WP-CLI as the WordPress filesystem owner:

```bash
docker exec -it -u www-data wordpress wp --path=/var/www/html --info
```

Inspect Docker resources:

```bash
docker image ls
docker volume ls
docker network ls
docker inspect mariadb
docker inspect wordpress
docker inspect nginx
```

## Service implementation

### MariaDB

The MariaDB image installs:

```text
mariadb-server
gettext-base
```

Its configuration listens on:

```text
0.0.0.0:3306
```

The entrypoint performs two independent checks:

- `/var/lib/mysql/mysql` for MariaDB system tables;
- `/var/lib/mysql/.inception_initialized` for completed project SQL initialization.

When system tables are missing, it runs `mariadb-install-db`. When project initialization is missing, it:

1. starts a temporary MariaDB server with networking disabled;
2. waits until the local socket is available;
3. renders `init.sql.template` with escaped values;
4. creates or updates the database and application account;
5. configures the root password;
6. shuts down the temporary server;
7. creates the initialization marker.

The final process is started with:

```sh
exec "$@"
```

The Dockerfile command is:

```text
mariadbd --user=mysql
```

This makes the real MariaDB server PID 1.

### WordPress and PHP-FPM

The WordPress image installs PHP-FPM, required PHP extensions, MariaDB client tools, and WP-CLI.

PHP-FPM listens on:

```text
0.0.0.0:9000
```

The WordPress entrypoint:

1. validates required variables and secret files;
2. rejects an administrator username containing `admin`;
3. downloads WordPress only when `wp-load.php` is missing;
4. waits for MariaDB using an authenticated TCP query;
5. creates `wp-config.php` only when missing;
6. installs WordPress only when it is not already installed;
7. creates the second user only when it does not exist;
8. starts PHP-FPM through `exec`.

The final command is:

```text
php-fpm8.2 -F
```

### NGINX

The NGINX image installs:

```text
nginx
gettext-base
```

Its entrypoint:

1. validates `DOMAIN_NAME`;
2. checks the configuration template, certificate, and private key;
3. renders the NGINX server configuration with `envsubst`;
4. runs `nginx -t`;
5. starts NGINX through `exec`.

The generated configuration:

- listens on port `443` for IPv4 and IPv6;
- enables TLS 1.2 and TLS 1.3 only;
- serves files from `/var/www/html`;
- forwards PHP requests to `wordpress:9000`;
- sets the FastCGI HTTPS parameter;
- uses the mounted certificate and private key.

The final command is:

```text
nginx -g daemon off;
```

## Network and DNS

All three services join the `inception` bridge network.

Test Docker DNS from NGINX:

```bash
docker exec nginx getent hosts wordpress
```

Test Docker DNS from WordPress:

```bash
docker exec wordpress getent hosts mariadb
```

Inspect the network:

```bash
docker network inspect inception_inception
```

The exact Docker network object name includes the Compose project name and may be shown as `inception_inception`.

Host networking, Compose `links`, and `--link` are not used.

## Ports

Check published ports:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected behavior:

```text
nginx       0.0.0.0:443->443/tcp
wordpress   9000/tcp
mariadb     3306/tcp
```

The WordPress and MariaDB entries are exposed only inside Docker and do not contain a host mapping.

Check listening host ports:

```bash
sudo ss -lntp | grep -E ':(80|443|3306|9000)\b' || true
```

Only host port `443` should belong to the stack.

## Volumes and persistence

The Compose file declares Docker named volumes with explicit names:

```text
mariadb_data
wordpress_data
```

They use the local driver with host-backed storage:

```text
mariadb_data  -> /home/tsargsya/data/mariadb
wordpress_data -> /home/tsargsya/data/wordpress
```

Container mount points are:

```text
mariadb_data   -> /var/lib/mysql
wordpress_data -> /var/www/html
```

NGINX mounts `wordpress_data` read-only so that it can resolve static files and validate PHP script paths without modifying the website.

Inspect the volumes:

```bash
docker volume inspect mariadb_data
docker volume inspect wordpress_data
```

Inspect host data without modifying it:

```bash
sudo find /home/tsargsya/data -maxdepth 2 -printf '%M %u:%g %p\n'
```

Persistence must be tested with `make down`, not `make fclean`:

1. create a WordPress post or another identifiable record;
2. run `make down`;
3. run `make`;
4. verify that the site and record still exist;
5. verify that initialization did not run again.

## Process and restart checks

Display PID 1 in each container:

```bash
for container in mariadb wordpress nginx
do
    echo "===== $container ====="
    docker exec "$container" sh -c \
        'tr "\000" " " </proc/1/cmdline; echo'
done
```

Expected main processes:

```text
mariadbd --user=mysql
php-fpm: master process
nginx: master process nginx -g daemon off;
```

Check restart policy and restart counters:

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format '{{.Name}} policy={{.HostConfig.RestartPolicy.Name}} restart_count={{.RestartCount}} status={{.State.Status}}' \
        "$container"
done
```

All services should use `on-failure`.

## HTTPS and TLS verification

Check the website:

```bash
curl -k -sS -o /dev/null \
    -w 'HTTPS status=%{http_code}\n' \
    https://tsargsya.42.fr/
```

Check TLS 1.2:

```bash
openssl s_client \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1_2 </dev/null
```

Check TLS 1.3:

```bash
openssl s_client \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1_3 </dev/null
```

TLS 1.0 and TLS 1.1 must be rejected.

Inspect certificate identity:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -subject \
    -issuer \
    -dates \
    -ext subjectAltName
```

## Debugging workflow

Use the following order instead of changing multiple files at once:

1. validate the resolved Compose configuration;
2. inspect container state;
3. inspect the affected service logs;
4. inspect the generated configuration inside the container;
5. test internal DNS and connectivity;
6. verify mounted files and permissions;
7. rebuild only the affected image;
8. recreate only the affected service when possible.

Basic commands:

```bash
docker compose -f srcs/docker-compose.yml config
docker compose -f srcs/docker-compose.yml ps -a
docker compose -f srcs/docker-compose.yml logs --tail=150 SERVICE
docker inspect SERVICE
```

Service-specific guides are available in:

```text
docs/mariadb.md
docs/wordpress.md
docs/nginx.md
```

## Complete validation

The complete mandatory-part test procedure is documented in:

```text
docs/mandatory-testing.md
```

It covers:

- clean Git state;
- required local tools;
- environment and secret files;
- cold cleanup and rebuild;
- PID 1;
- startup logs;
- domain and generated files;
- published ports;
- TLS versions;
- WordPress and MariaDB state;
- Docker DNS;
- persistence;
- crash restart behavior;
- Git and secret audit;
- final HTTPS result.

Run the guide from top to bottom before evaluation. Some sections are destructive, so read each warning before executing commands.

## Git and security checks

Confirm that secrets and private keys are ignored:

```bash
git check-ignore -v secrets/*.txt certificates/inception.key
```

Confirm that generated secret files are not tracked:

```bash
git ls-files secrets certificates
```

Only `.gitkeep` placeholders should be tracked from those directories.

Search tracked files for suspicious password assignments without printing actual local secret values:

```bash
git grep -n -E '(PASSWORD|PASSWD|SECRET|PRIVATE_KEY)[[:space:]]*=' || true
```

Inspect the final state:

```bash
git status --short
git log -1 --oneline
```

## Development workflow

A safe iteration cycle is:

```text
Edit one service
-> validate configuration or shell syntax
-> rebuild that service
-> recreate that service
-> inspect logs
-> run focused tests
-> run persistence-safe integration tests
-> commit the working state
```

Useful syntax checks include:

```bash
sh -n tools/configure_domain.sh
sh -n tools/generate_certificates.sh
sh -n srcs/requirements/mariadb/tools/docker-entrypoint.sh
sh -n srcs/requirements/wordpress/tools/docker-entrypoint.sh
sh -n srcs/requirements/nginx/tools/docker-entrypoint.sh
python3 -m py_compile tools/generate_secrets.py
```

After documentation or configuration changes, finish with:

```bash
docker compose -f srcs/docker-compose.yml config
git diff --check
git status --short
```

# Inception User Documentation

## Purpose

This document explains how an end user or administrator can start, stop, access, and check the complete Inception stack, including the bonus services.

The project provides eight Docker services:

- **NGINX** — HTTPS entrypoint and reverse proxy.
- **WordPress + PHP-FPM** — the main website application.
- **MariaDB** — WordPress database storage.
- **Redis** — WordPress object cache.
- **FTP** — file access to the WordPress volume.
- **Adminer** — browser-based MariaDB administration.
- **Static site** — a separate portfolio website.
- **Dockpeek** — web interface for Docker container/log inspection.

Most web services are exposed through NGINX on HTTPS port `443`. FTP additionally publishes port `21` and passive ports `21000-21010`.

## Requirements

Run the project inside the prepared Linux virtual machine. These commands must be available:

```text
docker
docker compose
make
python3
openssl
sudo
```

The Docker daemon must be running.

## First-time setup

### 1. Open the project directory

Run commands from the repository root, where the `Makefile` is located.

### 2. Create local credentials

Generate all required secret files:

```bash
python3 srcs/tools/generate_secrets.py
```

This creates:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
secrets/ftp_password.txt
secrets/dockpeek_password.txt
secrets/dockpeek_secret_key.txt
```

Existing non-empty files are preserved.

To enter credentials interactively:

```bash
python3 srcs/tools/generate_secrets.py --manual
```

Do not commit, display, or share these files. Newly created secret files use permission mode `600`.

### 3. Start the project

Run:

```bash
make
```

This prepares the persistent-data directories, configures the local domains, generates or validates the self-signed TLS certificate, builds the Docker images, and starts all containers.

The domain configuration step may request the user's `sudo` password because it updates `/etc/hosts`.

## Accessing the services

### WordPress

Website:

```text
https://tsargsya.42.fr
```

Administration panel:

```text
https://tsargsya.42.fr/wp-admin
```

Default usernames:

```text
Administrator: tsargsya
Second user:   writer
```

Passwords:

```text
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

### Adminer

Open:

```text
https://adminer.tsargsya.42.fr
```

Use the MariaDB application credentials:

```text
Server:   mariadb
Database: wordpress
Username: wpuser
Password: secrets/db_password.txt
```

Adminer connects to MariaDB through the private Docker network.

### Static portfolio

Open:

```text
https://portfolio.tsargsya.42.fr
```

This is a separate static website served by its own container and reverse-proxied through NGINX.

### Dockpeek

Open:

```text
https://dockpeek.tsargsya.42.fr
```

Login information:

```text
Username: dockpeek
Password: secrets/dockpeek_password.txt
```

Dockpeek is intended for infrastructure inspection. It can display Docker container information and logs, so access to it should be treated as administrative access.

### FTP

The FTP service mounts the same `wordpress_data` volume used by WordPress.

Connection settings:

```text
Host: 127.0.0.1
Port: 21
Username: ftpuser
Password: secrets/ftp_password.txt
Passive ports: 21000-21010
```

A graphical FTP client or command-line FTP client can be used. Passive mode should be enabled.

### Redis

Redis has no end-user web interface. It runs internally on port `6379` and is used by WordPress for object caching.

Redis is intentionally not published to the host.

## TLS certificate warning

The project uses a self-signed development certificate. A browser may display a security warning.

Before accepting the warning, verify that the address is one of the expected local domains:

```text
tsargsya.42.fr
adminer.tsargsya.42.fr
portfolio.tsargsya.42.fr
dockpeek.tsargsya.42.fr
```

## Credential locations

| File | Purpose |
|---|---|
| `secrets/db_root_password.txt` | MariaDB root password |
| `secrets/db_password.txt` | MariaDB `wpuser` password used by WordPress/Adminer |
| `secrets/wp_admin_password.txt` | WordPress administrator password |
| `secrets/wp_user_password.txt` | WordPress second-user password |
| `secrets/ftp_password.txt` | FTP user password |
| `secrets/dockpeek_password.txt` | Dockpeek login password |
| `secrets/dockpeek_secret_key.txt` | Dockpeek application secret key |

Inside the relevant containers, Docker mounts these values as files under `/run/secrets/`.

### Important credential warning

Some credentials are used during first-time application initialization. Replacing a local secret file after persistent application data has already been initialized does not necessarily update the password stored by the application.

For an existing installation, rotate the credential using the application's normal administration mechanism and keep the local secret files consistent with the intended configuration.

## Checking service status

Show all containers:

```bash
docker compose -f srcs/docker-compose.yml ps
```

A running complete stack should include:

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

Check the HTTPS services:

```bash
curl -k -I https://tsargsya.42.fr
curl -k -I https://adminer.tsargsya.42.fr
curl -k -I https://portfolio.tsargsya.42.fr
curl -k -I https://dockpeek.tsargsya.42.fr
```

Check Redis from its container:

```bash
docker exec redis redis-cli ping
```

Expected response:

```text
PONG
```

## Published ports

The stack should publish:

```text
443/tcp               NGINX HTTPS
21/tcp                FTP control connection
21000-21010/tcp       FTP passive connections
```

MariaDB `3306`, WordPress/PHP-FPM `9000`, Redis `6379`, Adminer `9000`, static-site `8080`, and Dockpeek `8000` remain internal to the Docker network.

## Viewing logs

Show logs for the whole stack:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=100
```

Show logs for one service:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=100 mariadb
docker compose -f srcs/docker-compose.yml logs --tail=100 wordpress
docker compose -f srcs/docker-compose.yml logs --tail=100 nginx
docker compose -f srcs/docker-compose.yml logs --tail=100 redis
docker compose -f srcs/docker-compose.yml logs --tail=100 ftp
docker compose -f srcs/docker-compose.yml logs --tail=100 adminer
docker compose -f srcs/docker-compose.yml logs --tail=100 static_site
docker compose -f srcs/docker-compose.yml logs --tail=100 dockpeek
```

Follow new logs in real time:

```bash
docker compose -f srcs/docker-compose.yml logs -f
```

Press `Ctrl+C` to stop following logs. This does not stop the containers.

## Starting and stopping the stack

### Start or update

```bash
make
```

Builds changed images when needed and starts the complete stack in detached mode.

### Stop while preserving data

```bash
make down
```

Containers and the project network are removed, but persistent MariaDB and WordPress data under `/home/tsargsya/data` remain.

Start again with:

```bash
make
```

### Remove containers and orphans

```bash
make clean
```

Persistent data is preserved.

### Completely reset the project

```bash
make fclean
```

This is destructive. It removes project containers, project images, Docker volume objects, the Docker network, and data under:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/wordpress
```

It does not remove local secret files or generated TLS certificate files.

### Rebuild from a clean data state

```bash
make re
```

This runs `make fclean` followed by a fresh start. Existing WordPress and MariaDB data are lost.

### Force image rebuild without deleting persistent data

```bash
make rebuild
```

This rebuilds images with `--no-cache` and then starts the stack again while preserving `/home/tsargsya/data`.

## Persistent data

Persistent application data is stored on the host in:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/wordpress
```

The WordPress volume is shared with the FTP container.

Data survives:

- container restarts;
- container recreation;
- `make down`;
- `make clean`;
- a later `make`.

Data does not survive `make fclean` or `make re`.

Do not manually edit MariaDB storage files while MariaDB is running.

## Common checks

### A website domain does not open

Verify local name resolution:

```bash
getent hosts tsargsya.42.fr
getent hosts adminer.tsargsya.42.fr
getent hosts portfolio.tsargsya.42.fr
getent hosts dockpeek.tsargsya.42.fr
```

They should resolve to:

```text
127.0.0.1
```

Then inspect NGINX and the target service:

```bash
docker compose -f srcs/docker-compose.yml ps -a
docker compose -f srcs/docker-compose.yml logs --tail=100 nginx
```

### A container is restarting

Inspect that service's logs instead of deleting persistent data immediately:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=150 SERVICE_NAME
```

Typical causes include missing secrets, invalid configuration, permission problems, or failed dependency/startup checks.

### Redis cache is not working

First verify Redis itself:

```bash
docker exec redis redis-cli ping
```

Then inspect WordPress and Redis logs:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=150 redis
docker compose -f srcs/docker-compose.yml logs --tail=150 wordpress
```

### FTP connection fails

Verify that the FTP container is running and that ports are published:

```bash
docker compose -f srcs/docker-compose.yml ps ftp
```

Confirm that the client uses passive mode and the passive range `21000-21010`.

### The browser reports a certificate warning

This is expected for the self-signed local certificate. Confirm the requested domain before accepting it.

## Additional help

Detailed service-specific documentation is available in:

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

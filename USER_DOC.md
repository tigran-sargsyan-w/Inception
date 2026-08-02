# Inception User Documentation

## Purpose

This document explains how an end user or administrator can start, stop, access, and check the Inception stack.

The project provides a WordPress website through HTTPS. It runs three services:

- **NGINX** receives HTTPS requests on port `443`.
- **WordPress with PHP-FPM** runs the website application.
- **MariaDB** stores the WordPress database.

Only NGINX is reachable from the host. WordPress and MariaDB communicate through the private Docker network.

## Requirements

The project must be run inside the prepared Linux virtual machine. The following commands must be available:

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

Run all commands from the repository root, where the `Makefile` is located.

### 2. Create local credentials

Generate the required password files:

```bash
python3 tools/generate_secrets.py
```

This creates four local files:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

The script does not replace an existing non-empty secret file.

To enter passwords manually, use:

```bash
python3 tools/generate_secrets.py --manual
```

Do not commit, display, or share these files. They are excluded from Git and should have permission mode `600`.

### 3. Start the project

Run:

```bash
make
```

The command prepares the host directories, configures the local domain, generates a self-signed TLS certificate, builds the Docker images, and starts the containers.

The domain configuration step may request the user's `sudo` password because it updates `/etc/hosts`.

## Accessing WordPress

Open the website at:

```text
https://tsargsya.42.fr
```

Open the administration panel at:

```text
https://tsargsya.42.fr/wp-admin
```

The default WordPress usernames are:

```text
Administrator: tsargsya
Second user:   writer
```

Their passwords are stored locally in:

```text
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

The TLS certificate is self-signed. A browser may display a security warning because the local certificate is not signed by a public certificate authority. Verify that the address is exactly `tsargsya.42.fr` before accepting the local certificate for development use.

## Credential locations

The project uses the following secret files:

| File | Purpose |
|---|---|
| `secrets/db_root_password.txt` | MariaDB root password |
| `secrets/db_password.txt` | MariaDB `wpuser` password used by WordPress |
| `secrets/wp_admin_password.txt` | WordPress administrator password |
| `secrets/wp_user_password.txt` | WordPress second-user password |

The container receives these values as files under `/run/secrets/`. Passwords are not stored in Dockerfiles or tracked environment files.

### Important credential warning

The secret files are used during initial database and WordPress configuration. Replacing a secret file after the persistent data has already been initialized does not automatically change the corresponding password inside MariaDB or WordPress.

For an existing installation, change application credentials through the relevant administration tool and keep the local secret files consistent with the intended next cold installation. Do not delete persistent data only to rotate a password unless a complete reset is actually intended.

## Checking service status

Show the current container state:

```bash
docker compose -f srcs/docker-compose.yml ps
```

A healthy running stack should show:

```text
mariadb     Up
wordpress   Up
nginx       Up
```

Only NGINX should publish a host port:

```text
0.0.0.0:443->443/tcp
```

MariaDB port `3306` and PHP-FPM port `9000` should remain internal.

Check the website from the terminal:

```bash
curl -k -I https://tsargsya.42.fr
```

A working response should contain an HTTP status such as `200 OK`.

## Viewing logs

Show logs for the complete stack:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=100
```

Show logs for one service:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=100 mariadb
docker compose -f srcs/docker-compose.yml logs --tail=100 wordpress
docker compose -f srcs/docker-compose.yml logs --tail=100 nginx
```

Follow new logs in real time:

```bash
docker compose -f srcs/docker-compose.yml logs -f
```

Press `Ctrl+C` to stop following logs. This does not stop the containers.

## Starting and stopping the stack

### Start or rebuild

```bash
make
```

This builds changed images when needed and starts the services in detached mode.

### Stop while preserving data

```bash
make down
```

This removes the project containers and network, but preserves the WordPress and MariaDB data stored under `/home/tsargsya/data`.

Start the project again with:

```bash
make
```

### Remove containers and orphans

```bash
make clean
```

This performs a Compose shutdown with orphan cleanup. Persistent host data is preserved.

### Completely reset the project

```bash
make fclean
```

This is destructive. It removes:

- project containers;
- project images;
- Docker volume objects;
- the project network;
- MariaDB data under `/home/tsargsya/data/mariadb`;
- WordPress files under `/home/tsargsya/data/wordpress`.

It does not remove the local secret files or generated TLS certificate files.

After `make fclean`, running `make` creates a new WordPress installation from the current configuration and secret files.

### Rebuild from a clean data state

```bash
make re
```

This runs `make fclean` and then starts the project again. Existing website and database data are lost.

## Persistent data

The project data is stored on the host in:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/wordpress
```

The MariaDB directory contains the database files. The WordPress directory contains the website files, plugins, themes, and uploaded content.

Data survives:

- container restart;
- container removal;
- `make down`;
- a later `make`.

Data does not survive `make fclean`, because that target deliberately removes `/home/tsargsya/data`.

Do not manually edit MariaDB storage files while MariaDB is running.

## Common checks

### The website does not open

Check that the domain resolves locally:

```bash
getent hosts tsargsya.42.fr
```

The expected address is:

```text
127.0.0.1
```

Then check container status and NGINX logs:

```bash
docker compose -f srcs/docker-compose.yml ps -a
docker compose -f srcs/docker-compose.yml logs --tail=100 nginx
```

### A container is restarting

Inspect the service logs:

```bash
docker compose -f srcs/docker-compose.yml logs --tail=150 mariadb
docker compose -f srcs/docker-compose.yml logs --tail=150 wordpress
docker compose -f srcs/docker-compose.yml logs --tail=150 nginx
```

Do not immediately delete the persistent data. The logs normally identify a missing secret, invalid configuration, permission problem, or service startup failure.

### The browser reports a certificate warning

This is expected for the self-signed development certificate. Confirm that the requested domain is `tsargsya.42.fr`.

### The domain configuration script reports a conflict

The script refuses to add the domain when `/etc/hosts` already maps `tsargsya.42.fr` to another address. Inspect the existing entries:

```bash
grep -n 'tsargsya\.42\.fr' /etc/hosts
```

Correct the conflicting local mapping before running `make` again.

## Additional help

Detailed project checks and service-specific troubleshooting are available in:

```text
docs/mandatory-testing.md
docs/mariadb.md
docs/wordpress.md
docs/nginx.md
```

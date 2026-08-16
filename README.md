# Inception – A Multi-Service Docker Infrastructure 🐳🌐

✅ **Status**: Completed  
🏫 **School**: 42 Lyon – Inception  
🏅 **Score**: 125/100  
🧰 **Stack**: Docker · Docker Compose · NGINX · WordPress · MariaDB · Redis · Adminer · FTP · DockPeek  
🐧 **Base Image**: Debian Bookworm

> *A complete multi-container web infrastructure built from custom Docker images, with HTTPS, persistent storage, caching, administration tools, FTP access, and container observability.*

---

## 📚 Table of Contents

* [📝 Description](#-description)
* [✨ Highlights](#-highlights)
* [🏗️ Architecture](#️-architecture)
* [🧩 Services](#-services)
* [🌐 Networking and TLS](#-networking-and-tls)
* [💾 Persistent Storage](#-persistent-storage)
* [🔐 Secrets and Configuration](#-secrets-and-configuration)
* [🚀 Instructions](#-instructions)

  * [Prerequisites](#prerequisites)
  * [Generate Secrets](#generate-secrets)
  * [Build and Start](#build-and-start)
  * [Access the Services](#access-the-services)
  * [Makefile Commands](#makefile-commands)
* [🧪 Testing](#-testing)
* [📂 Repository Layout](#-repository-layout)
* [🛡️ Security and Reliability](#️-security-and-reliability)
* [🧠 Key Technical Lessons](#-key-technical-lessons)
* [📖 Documentation](#-documentation)
* [🔗 Resources](#-resources)

---

## 📝 Description

**Inception** is a system-administration project focused on building a complete web infrastructure with **Docker** and **Docker Compose**.

Instead of relying on pre-built application images, every service is built from its own custom `Dockerfile` based on **Debian Bookworm**.

The final infrastructure consists of eight independent containers:

* **NGINX** — HTTPS entrypoint and reverse proxy;
* **WordPress + PHP-FPM** — main web application;
* **MariaDB** — persistent relational database;
* **Redis** — WordPress object cache;
* **FTP** — file access to the WordPress volume;
* **Adminer** — web-based database administration;
* **Static Site** — independent portfolio website;
* **Dockpeek** — Docker container and log observability interface.

The services communicate through a private Docker bridge network, while persistent WordPress and MariaDB data are stored outside the container writable layers.

The infrastructure also implements local TLS certificates, Docker secrets, automatic service restart, custom initialization scripts, persistent volumes, multiple HTTPS virtual hosts, and automated infrastructure tests.

The original submission-oriented documentation is preserved as [`README_Subject.md`](README_Subject.md).

---

## ✨ Highlights

* ✅ **8 isolated services**, each running in its own container
* ✅ Custom Docker images based on **Debian Bookworm**
* ✅ Infrastructure orchestrated with **Docker Compose**
* ✅ **NGINX** as the main HTTPS entrypoint
* ✅ **TLS 1.2 and TLS 1.3 only**
* ✅ WordPress served through **PHP-FPM**
* ✅ Persistent **MariaDB** database
* ✅ Persistent WordPress filesystem
* ✅ **Redis** object caching for WordPress
* ✅ **FTP** access to the shared WordPress volume
* ✅ **Adminer** database administration interface
* ✅ Independent static portfolio website
* ✅ **Dockpeek** container observability interface
* ✅ Private Docker bridge networking with service-name DNS
* ✅ Docker secrets for passwords and secret keys
* ✅ Automatic restart with `restart: on-failure`
* ✅ Foreground service processes and proper PID 1 handling
* ✅ Self-signed TLS certificate generation
* ✅ Automated cold-start, persistence, restart, network, TLS, and security testing

---

## 🏗️ Architecture

The complete infrastructure runs inside a Linux virtual machine.

```text
                                  Browser
                                     │
                                 HTTPS :443
                                     │
                                     ▼
                              ┌─────────────┐
                              │    NGINX    │
                              │ TLS / Proxy │
                              └──────┬──────┘
                                     │
              ┌──────────────────────┼─────────────────────┐
              │                      │                     │
              ▼                      ▼                     ▼
      ┌───────────────┐      ┌─────────────┐      ┌───────────────┐
      │   WordPress   │      │   Adminer   │      │  Static Site  │
      │ PHP-FPM :9000 │      │    :9000    │      │     :8080     │
      └───────┬───────┘      └──────┬──────┘      └───────────────┘
              │                      │
       ┌──────┴──────┐               │
       │             │               │
       ▼             ▼               ▼
┌─────────────┐ ┌───────────┐ ┌─────────────┐
│   MariaDB   │ │   Redis   │ │  Dockpeek   │
│    :3306    │ │   :6379   │ │    :8000    │
└──────┬──────┘ └───────────┘ └─────────────┘
       │
       ▼
┌─────────────────┐
│  mariadb_data   │
└─────────────────┘


Host
 │
 ├── HTTPS :443 ───────────────────────────────► NGINX
 │
 └── FTP :21 + :21000-21010 ─────────────────► FTP
                                                   │
                                                   ▼
                                          ┌─────────────────┐
                                          │ wordpress_data  │
                                          └─────────────────┘
                                                   ▲
                                                   │
                                              WordPress
```

All containers are connected to the private `inception` Docker bridge network.

Docker's internal DNS allows services to communicate using their service names:

```text
wordpress → mariadb:3306
wordpress → redis:6379
nginx     → wordpress:9000
nginx     → adminer:9000
nginx     → static_site:8080
nginx     → dockpeek:8000
```

---

## 🧩 Services

| Service         | Role                                                 | Internal Port | Host Exposure       |
| --------------- | ---------------------------------------------------- | ------------: | ------------------- |
| **NGINX**       | TLS termination, WordPress gateway and reverse proxy |         `443` | `443`               |
| **WordPress**   | WordPress application through PHP-FPM                |        `9000` | Internal only       |
| **MariaDB**     | WordPress relational database                        |        `3306` | Internal only       |
| **Redis**       | WordPress object cache                               |        `6379` | Internal only       |
| **Adminer**     | Database administration interface                    |        `9000` | Through NGINX       |
| **Static Site** | Independent portfolio website                        |        `8080` | Through NGINX       |
| **Dockpeek**    | Docker container and log viewer                      |        `8000` | Through NGINX       |
| **FTP**         | Access to WordPress files                            |          `21` | `21`, `21000-21010` |

Each service is built from a dedicated Dockerfile located under:

```text
srcs/requirements/
```

No ready-made application image is used for the project services.

---

## 🌐 Networking and TLS

The project uses a dedicated Docker bridge network:

```text
inception
```

This keeps internal services isolated from the host while still allowing containers to communicate through Docker DNS.

Only services that actually require host access publish ports.

For browser-based services, **NGINX is the single HTTPS entrypoint on port `443`**.

Four local HTTPS virtual hosts are configured:

```text
https://tsargsya.42.fr
https://adminer.tsargsya.42.fr
https://portfolio.tsargsya.42.fr
https://dockpeek.tsargsya.42.fr
```

NGINX accepts only:

```text
TLSv1.2
TLSv1.3
```

The local certificate and private key are generated automatically during project preparation.

FTP is exposed separately because the protocol requires its own control connection and passive data connections:

```text
21
21000-21010
```

---

## 💾 Persistent Storage

Containers are disposable, but the application data is not.

Two Docker named volumes are used:

| Volume           | Container Mount  | Host Storage                    |
| ---------------- | ---------------- | ------------------------------- |
| `mariadb_data`   | `/var/lib/mysql` | `/home/tsargsya/data/mariadb`   |
| `wordpress_data` | `/var/www/html`  | `/home/tsargsya/data/wordpress` |

The WordPress volume is shared between several services:

```text
WordPress  → read/write
NGINX      → read-only
FTP        → read/write
```

This means containers can be destroyed and recreated without losing the website or database.

For example:

```sh
make down
make
```

recreates the containers while preserving the persistent application data.

A full cleanup with:

```sh
make fclean
```

intentionally deletes the persistent data.

---

## 🔐 Secrets and Configuration

Normal configuration is stored in environment files under:

```text
srcs/.env
srcs/environment/
```

Examples include:

* domain names;
* database name;
* database username;
* WordPress usernames;
* FTP configuration;
* service hostnames.

Sensitive values are kept separately under:

```text
secrets/
```

The project uses the following local secret files:

```text
db_root_password.txt
db_password.txt
wp_admin_password.txt
wp_user_password.txt
ftp_password.txt
dockpeek_password.txt
dockpeek_secret_key.txt
```

Docker mounts the required secrets into selected containers under:

```text
/run/secrets/
```

Passwords and secret keys are therefore not stored inside Dockerfiles or tracked environment files.

The `secrets/` directory and private TLS key are excluded from Git.

---

## 🚀 Instructions

### Prerequisites

The project is intended to run inside a Linux virtual machine.

Required tools:

```text
Docker Engine
Docker Compose
GNU Make
Python 3
OpenSSL
sudo
```

The Docker daemon must be running.

This repository is configured for the 42 login:

```text
tsargsya
```

and uses:

```text
/home/tsargsya/data
```

for persistent storage.

### Generate Secrets

Before the first launch:

```sh
python3 srcs/tools/generate_secrets.py
```

The script automatically generates the required local credentials.

Existing non-empty secrets are preserved.

For manual password entry:

```sh
python3 srcs/tools/generate_secrets.py --manual
```

Generated secret files use restrictive filesystem permissions.

### Build and Start

From the repository root:

```sh
make
```

The default Makefile target:

1. creates the persistent storage directories;
2. configures the project domains;
3. generates or validates the TLS certificate;
4. builds all custom Docker images;
5. creates the Docker resources;
6. starts the complete infrastructure.

Check the running stack:

```sh
docker compose -f srcs/docker-compose.yml ps
```

Expected containers:

```text
mariadb
wordpress
nginx
redis
ftp
adminer
static_site
dockpeek
```

### Access the Services

#### WordPress

```text
https://tsargsya.42.fr
```

WordPress administration:

```text
https://tsargsya.42.fr/wp-admin
```

#### Adminer

```text
https://adminer.tsargsya.42.fr
```

#### Static Portfolio

```text
https://portfolio.tsargsya.42.fr
```

#### Dockpeek

```text
https://dockpeek.tsargsya.42.fr
```

#### FTP

```text
Host: 127.0.0.1
Port: 21
User: ftpuser
Passive ports: 21000-21010
```

The FTP password is stored locally in:

```text
secrets/ftp_password.txt
```

Because the HTTPS certificate is self-signed, browsers may display a local certificate warning.

### Makefile Commands

Build and start the infrastructure:

```sh
make
```

Stop the containers while preserving data:

```sh
make down
```

Remove containers and orphaned containers:

```sh
make clean
```

Remove containers, images, volumes and persistent application data:

```sh
make fclean
```

Perform a completely clean rebuild:

```sh
make re
```

Rebuild all images without Docker build cache while preserving persistent data:

```sh
make rebuild
```

---

## 🧪 Testing

The repository contains an automated mandatory infrastructure test runner:

```sh
./tools/test_mandatory.sh
```

List available test modes:

```sh
./tools/test_mandatory.sh list
```

Available test areas include:

```text
preflight
runtime
tls
wordpress
mariadb
network
persistence
restart
security
cold-start
full
```

Examples:

```sh
./tools/test_mandatory.sh runtime
```

```sh
./tools/test_mandatory.sh tls
```

```sh
./tools/test_mandatory.sh network
```

```sh
./tools/test_mandatory.sh persistence
```

```sh
./tools/test_mandatory.sh security
```

Run the complete acceptance suite:

```sh
./tools/test_mandatory.sh full
```

> **Warning:** `cold-start` and `full` are destructive tests. They remove the current WordPress and MariaDB persistent data before rebuilding the infrastructure.

The automated suite checks areas such as:

* Docker and Compose configuration;
* container state;
* PID 1 processes;
* restart policies;
* TLS certificate and protocol support;
* WordPress configuration;
* MariaDB users and permissions;
* Docker networking and internal DNS;
* volume sharing;
* persistence across container recreation;
* automatic recovery after process crashes;
* secret handling;
* forbidden runtime hacks;
* image tags and base images;
* final infrastructure health.

Test evidence is written to:

```text
logs/mandatory-test-YYYYMMDD-HHMMSS.log
```

---

## 📂 Repository Layout

```text
.
├── Makefile
├── README.md
├── README_Subject.md
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

Each service directory contains its own Dockerfile and, when required, configuration templates and initialization scripts.

---

## 🛡️ Security and Reliability

Several design choices keep the infrastructure predictable and reduce unnecessary exposure.

### Secrets

Sensitive credentials are stored outside tracked configuration and mounted only into containers that need them.

### Network Isolation

MariaDB, Redis, WordPress, Adminer, the static website, and Dockpeek do not need direct host exposure.

Docker bridge networking keeps this traffic internal.

### TLS

Browser-facing traffic enters through NGINX using TLS 1.2 or TLS 1.3.

### PID 1

Long-running services execute in the foreground.

Entrypoint scripts use `exec` so that the real application process becomes the container's PID 1.

No container is artificially kept alive using patterns such as:

```text
tail -f
sleep infinity
while true
```

### Restart Recovery

Every service uses:

```yaml
restart: on-failure
```

allowing Docker to restart a container when its main process crashes.

### Persistent Data

Application data is stored outside the container writable layers and therefore survives container recreation.

### Docker Socket

Dockpeek receives read-only filesystem access to:

```text
/var/run/docker.sock
```

The Docker socket remains a privileged interface even when mounted read-only, so access to the Dockpeek interface should be treated as infrastructure-level access.

---

## 🧠 Key Technical Lessons

This project combines several important system-administration concepts:

* how containers differ from virtual machines;
* how Docker images, containers, networks and volumes interact;
* how Docker Compose describes a multi-service infrastructure;
* how Docker's internal DNS enables service discovery;
* how reverse proxies route traffic between services;
* how NGINX communicates with PHP-FPM through FastCGI;
* how TLS termination works;
* how database initialization can be automated safely;
* how persistent data survives disposable containers;
* how Docker secrets differ from normal environment configuration;
* how PID 1 and Unix signals affect container shutdown and restart behavior;
* how Redis can be integrated as a WordPress object cache;
* how passive FTP requires multiple network connections;
* why the Docker socket is a security-sensitive interface;
* how to test infrastructure using cold starts, crash recovery, persistence checks, and security audits.

---

## 📖 Documentation

More detailed documentation is available throughout the repository.

### General Documentation

* [`USER_DOC.md`](USER_DOC.md) — using and administering the running infrastructure
* [`DEV_DOC.md`](DEV_DOC.md) — building, configuring and maintaining the project

### Service Documentation

* [NGINX](docs/nginx.md)
* [WordPress](docs/wordpress.md)
* [MariaDB](docs/mariadb.md)
* [Redis](docs/redis.md)
* [FTP](docs/ftp.md)
* [Adminer](docs/adminer.md)
* [Static Site](docs/static_site.md)
* [Dockpeek](docs/dockpeek.md)

### Testing Documentation

* [Mandatory Infrastructure Testing](docs/mandatory-testing.md)

---

## 🔗 Resources

### Docker

* [Docker Documentation](https://docs.docker.com/)
* [Dockerfile Reference](https://docs.docker.com/reference/dockerfile/)
* [Docker Compose Documentation](https://docs.docker.com/compose/)
* [Docker Networking](https://docs.docker.com/engine/network/)
* [Docker Storage](https://docs.docker.com/engine/storage/)
* [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/)

### Web Infrastructure

* [NGINX Documentation](https://nginx.org/en/docs/)
* [OpenSSL Documentation](https://docs.openssl.org/)
* [PHP Documentation](https://www.php.net/docs.php)
* [PHP-FPM Documentation](https://www.php.net/manual/en/install.fpm.php)

### Application and Data

* [WordPress Developer Resources](https://developer.wordpress.org/)
* [WP-CLI Documentation](https://wp-cli.org/)
* [MariaDB Documentation](https://mariadb.com/docs/)
* [Redis Documentation](https://redis.io/docs/)
* [Adminer](https://www.adminer.org/)

### Container Observability

* [Dockpeek](https://github.com/dockpeek/dockpeek)

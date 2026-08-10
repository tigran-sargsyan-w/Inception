## What Adminer is

Adminer is a lightweight web application for managing relational databases.

It is distributed as a single PHP file and provides a browser interface for:

- viewing databases and tables;
- running SQL queries;
- inspecting rows and columns;
- managing database objects;
- checking users and privileges, depending on the connected account.

## Role in this project

Adminer provides a graphical interface for inspecting the MariaDB database
used by WordPress.

The request flow is:

```text
Browser
→ HTTPS
→ NGINX :443
→ FastCGI
→ Adminer PHP-FPM :9000
→ MariaDB :3306
```

Adminer is stateless:

- it has no persistent volume;
- it does not store the WordPress database;
- it does not publish a host port;
- it does not receive database passwords through Docker secrets.

The database credentials are entered manually in the Adminer login form.

The MariaDB hostname must be:

```text
mariadb
```

and not:

```text
localhost
127.0.0.1
```

because MariaDB runs in a separate container.

## Important project properties

```text
Service name: adminer
Internal port: 9000
Published port: none
Protocol used by NGINX: FastCGI
Application file: /var/www/adminer/index.php
Database host: mariadb
Persistent volume: none
Docker secrets: none
```

# Adminer Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container → Logs → Process → Entrypoint → PHP-FPM → Adminer File → Port → Network → NGINX → Domain → TLS → MariaDB → HTTP Response
```

You do not need to memorize every command. Remember the troubleshooting order and use this page as a reference.

---

## 1. Check the container state

Run from the project root:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected result:

```text
adminer   Up   9000/tcp
```

Useful states:

- `Up` — the container's main process is running.
- `Restarting` — the entrypoint or PHP-FPM repeatedly exits with an error.
- `Exited (1)` — the container stopped with an error.
- `Exited (0)` — the container stopped normally.

Important:

> `Up` means that PHP-FPM is running. It does not guarantee that NGINX can reach Adminer, that the domain resolves, or that Adminer can connect to MariaDB.

Only NGINX should publish a port on the VM:

```text
nginx      published 443
adminer    internal 9000 only
wordpress  internal 9000 only
mariadb    internal 3306 only
```

---

## 2. Read the Adminer logs

```bash
docker logs adminer
```

Show only the last 100 lines:

```bash
docker logs --tail=100 adminer
```

Follow logs in real time:

```bash
docker logs -f adminer
```

An empty log can be normal when PHP-FPM starts successfully and no worker errors have occurred.

Common error categories:

- Adminer file is missing or empty;
- invalid PHP-FPM configuration;
- PHP-FPM startup failure;
- port `9000` is already used inside the container;
- permission denied while reading `/var/www/adminer/index.php`;
- missing PHP MySQL extension;
- NGINX cannot connect to PHP-FPM;
- MariaDB cannot be reached from Adminer.

Stop live log output with:

```text
Ctrl + C
```

---

## 3. Check the main process

Show the command running as PID 1:

```bash
docker exec adminer sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'
```

Expected result:

```text
PID 1: php-fpm8.2 -F
```

Inspect the process table:

```bash
docker exec adminer ps -o pid,ppid,user,comm,args
```

Expected main process:

```text
PID 1
User: root
Command: php-fpm8.2
Arguments: php-fpm: master process (...)
```

PHP-FPM workers should run as:

```text
www-data
```

The entrypoint finishes with:

```sh
exec "$@"
```

The Dockerfile provides:

```dockerfile
CMD ["php-fpm8.2", "-F"]
```

Therefore, PHP-FPM replaces the entrypoint process and becomes PID 1.

---

## 4. Check the configured entrypoint and command

Inspect the image configuration used by the container:

```bash
docker inspect adminer \
    --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
```

Expected result:

```text
Entrypoint=["/usr/local/bin/docker-entrypoint.sh"] Cmd=["php-fpm8.2","-F"]
```

Meaning:

```text
docker-entrypoint.sh
    → validates the Adminer file
    → executes php-fpm8.2 -F
```

Inspect the entrypoint inside the container:

```bash
docker exec adminer cat \
    /usr/local/bin/docker-entrypoint.sh
```

The important checks are:

```sh
ADMINER_FILE="/var/www/adminer/index.php"

if [ ! -s "$ADMINER_FILE" ]; then
    exit 1
fi

exec "$@"
```

---

## 5. Validate the PHP-FPM configuration

Run the PHP-FPM configuration test:

```bash
docker exec adminer php-fpm8.2 -t
```

Expected result:

```text
configuration file ... test is successful
```

For the complete resolved configuration:

```bash
docker exec adminer php-fpm8.2 -tt
```

Inspect the project pool configuration:

```bash
docker exec adminer cat \
    /etc/php/8.2/fpm/pool.d/www.conf
```

Expected important values:

```ini
[www]

user = www-data
group = www-data

listen = 9000

pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

clear_env = no

catch_workers_output = yes
decorate_workers_output = no
```

Meaning:

- PHP workers run as `www-data`;
- PHP-FPM accepts FastCGI connections on port `9000`;
- the number of workers changes dynamically;
- worker output is forwarded to Docker logs.

---

## 6. Check the Adminer file

Check that the file exists and is not empty:

```bash
docker exec adminer sh -c '
    test -s /var/www/adminer/index.php \
        && echo "Adminer file: OK"
'
```

Expected result:

```text
Adminer file: OK
```

Inspect the file:

```bash
docker exec adminer ls -lh \
    /var/www/adminer/index.php
```

Check PHP syntax:

```bash
docker exec adminer php -l \
    /var/www/adminer/index.php
```

Expected result:

```text
No syntax errors detected in /var/www/adminer/index.php
```

Check ownership and permissions:

```bash
docker exec adminer stat \
    -c '%U:%G %a %n' \
    /var/www/adminer \
    /var/www/adminer/index.php
```

Expected owner:

```text
www-data:www-data
```

The Adminer file is downloaded during the image build. It is not created when the container starts.

---

## 7. Check the Adminer version source

Inspect the Dockerfile:

```bash
grep -n 'ADMINER_VERSION' \
    srcs/requirements/adminer/Dockerfile
```

Expected value:

```text
ARG ADMINER_VERSION=5.5.1
```

The image downloads the MySQL/MariaDB English build:

```text
adminer-5.5.1-mysql-en.php
```

The version is pinned so that a future Adminer release does not silently change the image content.

The version can also be confirmed in the Adminer web interface.

---

## 8. Check PHP database extensions

List the required PHP modules:

```bash
docker exec adminer php -m \
    | grep -E '^(mysqli|PDO|pdo_mysql)$'
```

Expected modules:

```text
mysqli
PDO
pdo_mysql
```

These modules allow PHP and Adminer to communicate with MariaDB.

If `mysqli` or `pdo_mysql` is missing, verify that the image installs:

```text
php-mysql
```

---

## 9. Check the internal PHP-FPM port

Inspect the port declared by the image:

```bash
docker inspect adminer \
    --format '{{json .Config.ExposedPorts}}'
```

Expected result:

```text
{"9000/tcp":{}}
```

Check whether the port is published on the VM:

```bash
docker port adminer
```

Expected result:

```text
No output
```

This is intentional.

Port `9000` is used only inside the Docker network:

```text
NGINX → FastCGI → adminer:9000
```

Important:

> PHP-FPM speaks FastCGI, not HTTP or HTTPS. It must not be opened directly in a browser or published on the VM.

`EXPOSE 9000` documents the internal service port. It does not publish the port on the host.

---

## 10. Check the Docker network

List the Inception network:

```bash
docker network ls --filter name=inception
```

The generated network is normally:

```text
inception_inception
```

Inspect it:

```bash
docker network inspect inception_inception
```

The following services must appear in the same network:

```text
nginx
adminer
mariadb
wordpress
```

Adminer needs:

```text
NGINX → adminer
Adminer → MariaDB
```

No host port is needed for either connection.

---

## 11. Check Docker DNS

From NGINX, check that the Adminer service name resolves:

```bash
docker exec nginx getent hosts adminer
```

Expected result:

```text
<container-ip> adminer
```

From Adminer, check that the MariaDB service name resolves:

```bash
docker exec adminer getent hosts mariadb
```

Expected result:

```text
<container-ip> mariadb
```

Correct service names:

```text
NGINX upstream: adminer:9000
Adminer database server: mariadb
```

Do not use:

```text
localhost
127.0.0.1
```

Inside the Adminer container, `localhost` refers to Adminer itself, not to the MariaDB container.

---

## 12. Check TCP reachability to MariaDB

Adminer does not contain the MariaDB command-line client.

Use PHP to test whether the MariaDB TCP port is reachable:

```bash
docker exec adminer php -r '
$socket = @fsockopen("mariadb", 3306, $errno, $error, 3);

if (!$socket) {
    fwrite(STDERR, "Connection failed: $errno $error\n");
    exit(1);
}

echo "mariadb:3306 is reachable\n";
fclose($socket);
'
```

Expected result:

```text
mariadb:3306 is reachable
```

This confirms:

- Docker DNS resolves `mariadb`;
- the MariaDB container is reachable;
- port `3306` accepts TCP connections.

It does not confirm database authentication. Authentication is tested through the Adminer login form.

---

## 13. Validate the NGINX configuration

Run:

```bash
docker exec nginx nginx -t
```

Expected result:

```text
syntax is ok
test is successful
```

Print the active project configuration:

```bash
docker exec nginx cat \
    /etc/nginx/conf.d/default.conf
```

The Adminer server block must contain:

```nginx
server_name adminer.tsargsya.42.fr;

fastcgi_pass adminer:9000;

fastcgi_param SCRIPT_FILENAME /var/www/adminer/index.php;
fastcgi_param SCRIPT_NAME /index.php;
fastcgi_param HTTPS on;
```

Important:

> `/var/www/adminer/index.php` is a path inside the Adminer container. NGINX passes this path to Adminer's PHP-FPM process through FastCGI.

NGINX does not need an Adminer volume because the PHP file is executed inside the Adminer container.

---

## 14. Check NGINX-to-Adminer errors

Show NGINX errors:

```bash
docker exec nginx tail -n 100 \
    /var/log/nginx/error.log
```

Common errors:

```text
host not found in upstream "adminer"
```

Meaning:

```text
Docker DNS cannot resolve Adminer,
or NGINX and Adminer are not in the same network.
```

```text
connect() failed (111: Connection refused) while connecting to upstream
```

Meaning:

```text
NGINX resolved Adminer,
but PHP-FPM is not listening on port 9000.
```

```text
Primary script unknown
```

Meaning:

```text
SCRIPT_FILENAME does not match the Adminer file path,
or the file is missing inside the Adminer container.
```

```text
502 Bad Gateway
```

Normally indicates an upstream FastCGI problem. Check:

```text
Adminer container state
PHP-FPM process
Docker DNS
port 9000
SCRIPT_FILENAME
```

---

## 15. Check local domain resolution

Check the Adminer domain:

```bash
getent hosts adminer.tsargsya.42.fr
```

Expected result:

```text
127.0.0.1 adminer.tsargsya.42.fr
```

Inspect the `/etc/hosts` entry:

```bash
grep -n 'adminer.tsargsya.42.fr' \
    /etc/hosts
```

Expected mapping:

```text
127.0.0.1    adminer.tsargsya.42.fr    # Inception
```

Check that only one mapping exists:

```bash
grep -c 'adminer.tsargsya.42.fr' \
    /etc/hosts
```

Expected result:

```text
1
```

The mapping is prepared by:

```text
srcs/tools/configure_domain.sh
```

The source value is:

```text
ADMINER_DOMAIN=adminer.tsargsya.42.fr
```

inside:

```text
srcs/.env
```

Important:

> Wildcard TLS certificates do not provide DNS resolution. The domain must still resolve to the VM through `/etc/hosts` or another DNS mechanism.

---

## 16. Check the Adminer TLS hostname

Inspect the Subject Alternative Name:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -ext subjectAltName
```

Expected result:

```text
DNS:tsargsya.42.fr, DNS:*.tsargsya.42.fr
```

Check the main domain:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkhost tsargsya.42.fr
```

Check the Adminer domain:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkhost adminer.tsargsya.42.fr
```

Expected result:

```text
Hostname ... does match certificate
```

Meaning:

```text
DNS:tsargsya.42.fr
→ covers the main WordPress domain

DNS:*.tsargsya.42.fr
→ covers adminer.tsargsya.42.fr and other first-level subdomains
```

The wildcard entry does not replace the explicit main-domain entry.

---

## 17. Test the HTTPS response

Check only the response headers:

```bash
curl -k -I \
    https://adminer.tsargsya.42.fr
```

Expected result:

```text
HTTP/1.1 200 OK
```

Compact status check:

```bash
curl -k -sS -o /dev/null \
    -w 'Adminer: HTTP %{http_code}\n' \
    https://adminer.tsargsya.42.fr
```

Expected result:

```text
Adminer: HTTP 200
```

Meaning of `-k`:

```text
Ignore public certificate-authority verification
Keep using an encrypted HTTPS connection
```

The option is needed because the project uses a self-signed certificate.

---

## 18. Check the Adminer login

Open:

```text
https://adminer.tsargsya.42.fr
```

Use:

```text
System:   MySQL
Server:   mariadb
Username: wpuser
Password: value from secrets/db_password.txt
Database: wordpress
```

Important:

> Use `mariadb` as the server. Do not use `localhost`.

A successful login confirms:

- the Adminer web application works;
- PHP-FPM executes the Adminer file;
- the PHP MySQL extension works;
- Docker DNS resolves `mariadb`;
- MariaDB accepts the connection;
- the username and password are correct;
- the `wordpress` database exists;
- `wpuser` has access to the database.

A wrong password normally produces an authentication error.

An incorrect server name normally produces a connection or hostname error.

Do not include database passwords in screenshots, logs, documentation, or Git commits.

---

## 19. Check the WordPress tables

After logging in, select the `wordpress` database.

Expected tables include:

```text
wp_commentmeta
wp_comments
wp_links
wp_options
wp_postmeta
wp_posts
wp_term_relationships
wp_term_taxonomy
wp_termmeta
wp_terms
wp_usermeta
wp_users
```

The exact number can change when plugins or other WordPress features create additional tables.

Seeing the tables confirms that Adminer is connected to the correct database.

For an independent command-line check:

```bash
docker exec mariadb sh -c '
    MYSQL_PWD="$(tr -d "\r\n" < /run/secrets/db_password)" \
    mariadb \
        --protocol=tcp \
        --host=127.0.0.1 \
        --port=3306 \
        --user=wpuser \
        --database=wordpress \
        --execute="SHOW TABLES"
'
```

Do not print the password itself.

---

## 20. Understand the security boundary

Adminer is a database administration tool.

The account entered in the login form determines what Adminer can do.

With:

```text
wpuser
```

Adminer should be limited to the privileges granted to that MariaDB account.

Check the grants from MariaDB:

```sql
SHOW GRANTS FOR 'wpuser'@'%';
```

Expected project privilege:

```text
GRANT ALL PRIVILEGES ON `wordpress`.* TO `wpuser`@`%`
```

Important:

- Adminer must not publish its PHP-FPM port directly;
- external access goes through NGINX and HTTPS;
- Adminer should not receive the MariaDB root password through environment variables;
- database credentials are entered by the user at login;
- logging in with a powerful database account gives Adminer the same powerful permissions.

---

## 21. Confirm that Adminer is stateless

Inspect container mounts:

```bash
docker inspect adminer \
    --format '{{json .Mounts}}'
```

Expected result:

```text
[]
```

Adminer does not need:

```text
a persistent volume
a bind mount
a Docker secret
a project data directory
```

The application file is part of the image.

The actual database data remains in MariaDB's persistent volume.

Removing and recreating the Adminer container does not remove WordPress data.

---

## 22. Check the resolved Compose configuration

Show only the Adminer service:

```bash
docker compose -f srcs/docker-compose.yml \
    config adminer
```

Or inspect the complete resolved configuration:

```bash
docker compose -f srcs/docker-compose.yml config
```

Expected Adminer properties:

```text
build context: ./requirements/adminer
image: adminer:inception
container_name: adminer
restart: on-failure
depends_on: mariadb
network: inception
no ports
no volumes
no secrets
```

Important:

> `depends_on` controls startup order. It does not prove that MariaDB is already ready to authenticate connections.

---

## 23. Restart or rebuild Adminer

Restart the existing container:

```bash
docker compose -f srcs/docker-compose.yml \
    restart adminer
```

Rebuild and recreate only Adminer:

```bash
docker compose -f srcs/docker-compose.yml \
    up -d --build --force-recreate adminer
```

Normal project startup:

```bash
make
```

Rebuild all images without Docker cache while preserving data:

```bash
make rebuild
```

The `rebuild` target:

```text
stops containers
prepares domains and certificates
builds all images with --no-cache
starts all services
preserves MariaDB and WordPress data
```

Do not use `make re` for a routine rebuild because it performs the destructive `fclean` path first.

After restarting or rebuilding, check:

```bash
docker compose -f srcs/docker-compose.yml ps

curl -k -sS -o /dev/null \
    -w 'Adminer: HTTP %{http_code}\n' \
    https://adminer.tsargsya.42.fr
```

---

## 24. Test the entrypoint failure path

The entrypoint must refuse to start when the Adminer file is missing.

Run a temporary container:

```bash
docker run --rm \
    --entrypoint sh \
    adminer:inception \
    -c '
        rm -f /var/www/adminer/index.php
        exec /usr/local/bin/docker-entrypoint.sh php-fpm8.2 -F
    '
```

Expected error:

```text
Adminer entrypoint error: file is missing or empty: /var/www/adminer/index.php
```

Expected exit status:

```text
non-zero
```

This test modifies only the temporary container. It does not change the image or the running Adminer service.

---

# Fast Diagnostic Path

For a quick investigation, start with:

```bash
docker compose -f srcs/docker-compose.yml ps

docker logs --tail=100 adminer

docker exec adminer sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'

docker exec adminer php-fpm8.2 -t

docker exec adminer test -s \
    /var/www/adminer/index.php

docker exec nginx getent hosts adminer

docker exec adminer getent hosts mariadb

docker exec nginx nginx -t

getent hosts adminer.tsargsya.42.fr

curl -k -I \
    https://adminer.tsargsya.42.fr
```

Then test the database login in the browser:

```text
System:   MySQL
Server:   mariadb
Username: wpuser
Database: wordpress
```

---

# Troubleshooting Logic to Remember

```text
1. Is the Adminer container running?
2. What do the Adminer logs say?
3. Is php-fpm8.2 the PID 1 process?
4. Did the entrypoint validate the Adminer file?
5. Is the PHP-FPM configuration valid?
6. Does /var/www/adminer/index.php exist and contain valid PHP?
7. Are mysqli and pdo_mysql installed?
8. Is port 9000 internal and not published?
9. Are NGINX, Adminer and MariaDB in the same Docker network?
10. Does NGINX resolve adminer?
11. Does Adminer resolve mariadb?
12. Can Adminer reach mariadb:3306?
13. Does NGINX use fastcgi_pass adminer:9000?
14. Does SCRIPT_FILENAME point to /var/www/adminer/index.php?
15. Does adminer.tsargsya.42.fr resolve to 127.0.0.1?
16. Does the TLS certificate match adminer.tsargsya.42.fr?
17. Does HTTPS return HTTP 200?
18. Can wpuser log in and see the WordPress tables?
```

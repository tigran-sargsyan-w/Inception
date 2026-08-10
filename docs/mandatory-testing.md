# Mandatory Part Full Test Guide

This document validates the complete mandatory part of the Inception project from a clean state.

It is an end-to-end acceptance test, not a troubleshooting guide. For service-specific diagnosis, use:

- [MariaDB troubleshooting](./mariadb.md)
- [WordPress troubleshooting](./wordpress.md)
- [NGINX troubleshooting](./nginx.md)

Run every command from the project root unless another location is explicitly mentioned.

---

<a id="test-flow"></a>
# Test Flow

Use this navigation to run the complete test from top to bottom or jump directly to a specific validation area.

1. [Pre-flight checks](#pre-flight-checks)
2. [Complete cleanup](#complete-cleanup)
3. [Cold build and startup](#cold-build-and-startup)
4. [Main process and PID 1](#main-process-and-pid-1)
5. [Startup logs](#startup-logs)
6. [Generated files, domain, and host data](#generated-files-domain-and-host-data)
7. [HTTPS and published ports](#https-and-published-ports)
8. [TLS protocol tests](#tls-protocol-tests)
9. [WordPress validation](#wordpress-validation)
10. [MariaDB validation](#mariadb-validation)
11. [Docker network and DNS](#docker-network-and-dns)
12. [Persistence test](#persistence-test)
13. [Crash restart test](#crash-restart-test)
14. [Git and security audit](#git-and-security-audit)
15. [Remove persistence-test data](#remove-persistence-test-data)
16. [Final acceptance check](#final-acceptance-check)

Additional references:

- [Important safety warning](#important-safety-warning)
- [Mandatory acceptance checklist](#mandatory-acceptance-checklist)
- [Validated baseline](#validated-baseline)

```text
Pre-flight
→ Complete cleanup
→ Cold build and startup
→ Containers and PID 1
→ Logs
→ Domain and certificates
→ HTTPS and ports
→ TLS versions
→ WordPress
→ MariaDB
→ Docker network and DNS
→ Persistence
→ Crash restart
→ Git and security audit
→ Final state
```

---

<a id="important-safety-warning"></a>
# Important Safety Warning

Some sections are destructive.

The following command removes:

- the project containers;
- the project images;
- the project network;
- the Docker volume objects;
- all MariaDB data under `/home/tsargsya/data/mariadb`;
- all WordPress data under `/home/tsargsya/data/wordpress`.

```bash
make fclean
```

Do not run the cold-start section when the current WordPress or MariaDB data must be preserved.

The persistence test uses:

```bash
make down
```

It must not use `make fclean`, because the purpose is to confirm that data survives container removal.

---

<a id="pre-flight-checks"></a>
# 1. Pre-flight Checks

## 1.1 Check the Git state

```bash
git branch --show-current
git status --short
git log -1 --oneline
```

Expected branch:

```text
main
```

Expected working tree:

```text
No output from git status --short
```

A clean working tree ensures that the test is performed against the committed project state.

---

## 1.2 Check the required tools

```bash
docker --version
docker compose version
python3 --version
openssl version
curl --version | head -n 1
sudo -v
```

Confirm that the Docker daemon is running:

```bash
docker info >/dev/null \
    && echo "Docker daemon: OK"
```

Expected result:

```text
Docker daemon: OK
```

---

## 1.3 Check environment files

```bash
printf '\n--- srcs/.env ---\n'
cat srcs/.env

printf '\n--- database.env ---\n'
cat srcs/environment/database.env

printf '\n--- wordpress.env ---\n'
cat srcs/environment/wordpress.env
```

Expected important values:

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

Passwords must not be stored in these environment files.

---

## 1.4 Check local secret files

Required files:

```text
secrets/db_root_password.txt
secrets/db_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Check that every file exists and is not empty:

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
```

Expected result:

```text
OK: secrets/db_root_password.txt
OK: secrets/db_password.txt
OK: secrets/wp_admin_password.txt
OK: secrets/wp_user_password.txt
```

Check permissions without printing secret values:

```bash
stat -c '%a %U:%G %n' secrets/*.txt
```

Expected mode:

```text
600
```

If the files do not exist, generate them before continuing:

```bash
python3 srcs/tools/generate_secrets.py
```

Do not print secret contents into the terminal, logs, screenshots, or documentation.

---

## 1.5 Validate the resolved Compose configuration

```bash
docker compose -f srcs/docker-compose.yml config
```

The command must complete without an error.

Check the declared services:

```bash
docker compose -f srcs/docker-compose.yml config --services
```

Expected result:

```text
mariadb
wordpress
nginx
```

Check images:

```bash
docker compose -f srcs/docker-compose.yml config --images
```

Expected images:

```text
mariadb:inception
wordpress:inception
nginx:inception
```

The order may differ.

Check volumes:

```bash
docker compose -f srcs/docker-compose.yml config --volumes
```

Expected result:

```text
mariadb_data
wordpress_data
```

Check networks:

```bash
docker compose -f srcs/docker-compose.yml config --networks
```

Expected result:

```text
inception
```

---

<a id="complete-cleanup"></a>
# 2. Complete Cleanup

This section performs a destructive reset.

## 2.1 Record the current state

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

---

## 2.2 Remove the complete project infrastructure

```bash
make fclean
```

The target should remove:

- `mariadb`;
- `wordpress`;
- `nginx`;
- `mariadb:inception`;
- `wordpress:inception`;
- `nginx:inception`;
- `mariadb_data`;
- `wordpress_data`;
- `inception_inception`;
- `/home/tsargsya/data`.

---

## 2.3 Verify the cleanup

```bash
echo
echo "===== COMPOSE CONTAINERS ====="
docker compose -f srcs/docker-compose.yml ps -a

echo
echo "===== INCEPTION CONTAINERS ====="
docker ps -a \
    --filter name='^/mariadb$' \
    --filter name='^/wordpress$' \
    --filter name='^/nginx$'

echo
echo "===== INCEPTION IMAGES ====="
docker image ls \
    --format '{{.Repository}}:{{.Tag}}' \
    | grep -E '^(mariadb|wordpress|nginx):inception$' \
    || echo "No Inception images"

echo
echo "===== INCEPTION VOLUMES ====="
docker volume ls \
    --format '{{.Name}}' \
    | grep -E '^(mariadb_data|wordpress_data)$' \
    || echo "No Inception volumes"

echo
echo "===== INCEPTION NETWORK ====="
docker network ls \
    --format '{{.Name}}' \
    | grep '^inception_inception$' \
    || echo "No Inception network"

echo
echo "===== HOST DATA DIRECTORY ====="
if [ -e /home/tsargsya/data ]; then
    sudo find /home/tsargsya/data \
        -maxdepth 2 \
        -printf '%M %u:%g %p\n'
else
    echo "/home/tsargsya/data was removed"
fi
```

Expected important results:

```text
No Inception images
No Inception volumes
No Inception network
/home/tsargsya/data was removed
```

The container tables must be empty.

---

## 2.4 Remove generated certificates for a true cold start

`make fclean` removes project data but does not remove generated TLS files.

Remove them manually:

```bash
rm -f \
    certificates/inception.crt \
    certificates/inception.key
```

Check the directory:

```bash
ls -la certificates
```

Only `.gitkeep` should remain.

Do not remove the secret files.

---

<a id="cold-build-and-startup"></a>
# 3. Cold Build and Startup

## 3.1 Build and start the complete infrastructure

```bash
time make
```

The normal execution flow is:

```text
Create host data directories
→ Configure tsargsya.42.fr
→ Generate TLS certificate and key
→ Build MariaDB image
→ Build WordPress image
→ Build NGINX image
→ Create Docker network
→ Create two named volumes
→ Start MariaDB
→ Start WordPress
→ Start NGINX
```

The command must finish without `Error`.

Wait for initialization:

```bash
sleep 15
```

---

## 3.2 Check container state

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

Expected state:

```text
mariadb     Up
wordpress   Up
nginx       Up
```

Invalid states include:

```text
Restarting
Exited
Created
Dead
```

Only NGINX should publish a host port:

```text
nginx       0.0.0.0:443->443/tcp
wordpress   9000/tcp
mariadb     3306/tcp
```

The WordPress and MariaDB ports shown without a host mapping are internal container ports.

---

## 3.3 Check restart counters and process state

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format '{{.Name}} status={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} exit_code={{.State.ExitCode}} pid={{.State.Pid}}' \
        "$container"
done
```

Expected initial state:

```text
status=running
running=true
restart_count=0
exit_code=0
```

---

<a id="main-process-and-pid-1"></a>
# 4. Main Process and PID 1

Check the command running as PID 1:

```bash
for container in mariadb wordpress nginx
do
    echo
    echo "===== $container PID 1 ====="

    docker exec "$container" sh -c \
        'printf "PID 1 command: "; tr "\000" " " </proc/1/cmdline; echo'
done
```

Expected processes:

```text
mariadb:
mariadbd --user=mysql

wordpress:
php-fpm: master process (/etc/php/8.2/fpm/php-fpm.conf)

nginx:
nginx: master process nginx -g daemon off;
```

This confirms that the real server process is PID 1.

The containers must not use shell commands such as:

```text
tail -f
sleep infinity
while true
```

to stay alive.

---

<a id="startup-logs"></a>
# 5. Startup Logs

## 5.1 MariaDB logs

```bash
docker compose -f srcs/docker-compose.yml \
    logs --no-color --tail=120 mariadb
```

Expected cold-start messages include:

```text
Initializing MariaDB system tables...
Configuring the Inception database...
MariaDB initialization completed.
ready for connections
```

The following warning is acceptable when MariaDB successfully falls back to another I/O implementation:

```text
io_uring_queue_init() failed
falling back to libaio
```

The final MariaDB server must listen on:

```text
0.0.0.0:3306
```

---

## 5.2 WordPress logs

```bash
docker compose -f srcs/docker-compose.yml \
    logs --no-color --tail=120 wordpress
```

Expected cold-start messages include:

```text
Downloading WordPress...
WordPress downloaded.
Waiting for MariaDB...
MariaDB is ready.
Creating wp-config.php...
wp-config.php created.
Installing WordPress...
WordPress installed.
Creating the second WordPress user...
Second WordPress user created.
```

---

## 5.3 NGINX logs

```bash
docker compose -f srcs/docker-compose.yml \
    logs --no-color --tail=120 nginx
```

Expected result:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

---

<a id="generated-files-domain-and-host-data"></a>
# 6. Generated Files, Domain, and Host Data

## 6.1 Check generated certificate permissions

```bash
stat -c '%a %U:%G %n' \
    certificates/inception.crt \
    certificates/inception.key
```

Expected modes:

```text
644 certificates/inception.crt
600 certificates/inception.key
```

---

## 6.2 Inspect the certificate

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -subject \
    -issuer \
    -dates \
    -ext subjectAltName
```

Expected domain:

```text
CN=tsargsya.42.fr
DNS:tsargsya.42.fr
```

A self-signed issuer is expected.

---

## 6.3 Check local domain resolution

```bash
getent hosts tsargsya.42.fr
```

Expected result:

```text
127.0.0.1 tsargsya.42.fr
```

Inspect the hosts file entry:

```bash
grep -n 'tsargsya\.42\.fr' /etc/hosts
```

---

## 6.4 Check persistent host directories

```bash
sudo find /home/tsargsya/data \
    -maxdepth 2 \
    -printf '%M %u:%g %p\n' \
    | head -n 80
```

Expected important paths:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/mariadb/mysql
/home/tsargsya/data/mariadb/wordpress
/home/tsargsya/data/mariadb/.inception_initialized

/home/tsargsya/data/wordpress
/home/tsargsya/data/wordpress/wp-admin
/home/tsargsya/data/wordpress/wp-content
/home/tsargsya/data/wordpress/wp-includes
/home/tsargsya/data/wordpress/wp-config.php
```

Host usernames may differ from container usernames because the host resolves the same numeric UID and GID through its own `/etc/passwd` and `/etc/group` files.

---

<a id="https-and-published-ports"></a>
# 7. HTTPS and Published Ports

## 7.1 Check the home page

```bash
curl -k -sS \
    -o /dev/null \
    -w 'HTTPS status=%{http_code} remote_ip=%{remote_ip} HTTP/%{http_version}\n' \
    https://tsargsya.42.fr/
```

Expected result:

```text
HTTPS status=200
```

Check the page title:

```bash
curl -k -sS https://tsargsya.42.fr/ \
    | grep -o '<title>[^<]*' \
    | head -n 1
```

Expected title:

```text
<title>Inception
```

---

## 7.2 Check the administrator page

```bash
curl -k -sS \
    -o /dev/null \
    -w 'WP-ADMIN status=%{http_code} redirect=%{redirect_url}\n' \
    https://tsargsya.42.fr/wp-admin/
```

Expected behavior:

```text
302 redirect to wp-login.php
```

A `200` response may also be valid depending on the WordPress version and authentication state.

---

## 7.3 Confirm that port 80 is closed

```bash
if curl -4 -sS \
    --connect-timeout 3 \
    -o /dev/null \
    http://tsargsya.42.fr/ \
    2>/dev/null
then
    echo "FAIL: port 80 accepts connections"
else
    echo "PASS: port 80 is closed"
fi
```

Expected result:

```text
PASS: port 80 is closed
```

---

## 7.4 Check Docker port bindings

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format '{{.Name}} PortBindings={{json .HostConfig.PortBindings}}' \
        "$container"
done
```

Expected result:

```text
/mariadb PortBindings={}
/wordpress PortBindings={}
/nginx PortBindings={"443/tcp":[...]}
```

Check host sockets:

```bash
sudo ss -ltnp \
    | grep -E ':(443|3306|9000)\b' \
    || true
```

Expected host listening port:

```text
443
```

Ports `3306` and `9000` must not be published on the VM.

---

<a id="tls-protocol-tests"></a>
# 8. TLS Protocol Tests

The certificate is self-signed, so a certificate verification warning is expected unless the certificate is explicitly trusted.

## 8.1 Test TLS 1.2

```bash
openssl s_client \
    -brief \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1_2 \
    </dev/null 2>&1 \
    | grep -E 'Protocol version|Ciphersuite|Verification error'
```

Expected protocol:

```text
Protocol version: TLSv1.2
```

---

## 8.2 Test TLS 1.3

```bash
openssl s_client \
    -brief \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1_3 \
    </dev/null 2>&1 \
    | grep -E 'Protocol version|Ciphersuite|Verification error'
```

Expected protocol:

```text
Protocol version: TLSv1.3
```

---

## 8.3 Confirm that TLS 1.0 and TLS 1.1 are rejected

```bash
for version in tls1 tls1_1
do
    echo
    echo "===== Testing $version ====="

    if openssl s_client \
        -brief \
        -connect tsargsya.42.fr:443 \
        -servername tsargsya.42.fr \
        "-$version" \
        -cipher 'ALL:@SECLEVEL=0' \
        </dev/null >"/tmp/inception-${version}.log" 2>&1
    then
        echo "FAIL: $version connection succeeded"
    else
        echo "PASS: $version connection rejected"
        tail -n 4 "/tmp/inception-${version}.log"
    fi
done
```

Expected result:

```text
PASS: tls1 connection rejected
PASS: tls1_1 connection rejected
```

A typical rejection contains:

```text
tlsv1 alert protocol version
SSL alert number 70
```

---

<a id="wordpress-validation"></a>
# 9. WordPress Validation

## 9.1 Confirm that WordPress is installed

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html core is-installed \
    && echo "PASS: WordPress is installed"
```

Expected result:

```text
PASS: WordPress is installed
```

Check the installed version:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html core version
```

The exact version may change when a new WordPress release becomes available.

---

## 9.2 Check the site configuration

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html option get siteurl

docker exec -u www-data wordpress \
    wp --path=/var/www/html option get home

docker exec -u www-data wordpress \
    wp --path=/var/www/html option get blogname
```

Expected values:

```text
https://tsargsya.42.fr
https://tsargsya.42.fr
Inception
```

---

## 9.3 Check WordPress users

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html user list \
    --fields=ID,user_login,user_email,roles \
    --format=table
```

Expected users:

```text
tsargsya   administrator
writer     author
```

The administrator username must not contain:

```text
admin
administrator
```

---

<a id="mariadb-validation"></a>
# 10. MariaDB Validation

## 10.1 Check root access, databases, and users

The command reads the secret inside the container and does not print the password:

```bash
docker exec mariadb sh -c '
MYSQL_PWD="$(cat /run/secrets/db_root_password)" \
mariadb \
    --protocol=socket \
    --socket=/run/mysqld/mysqld.sock \
    --user=root \
    --execute="
        SHOW DATABASES;

        SELECT User, Host
        FROM mysql.user
        ORDER BY User, Host;
    "
'
```

Expected project database:

```text
wordpress
```

Expected application account:

```text
wpuser   %
```

---

## 10.2 Test the application account

```bash
docker exec mariadb sh -c '
MYSQL_PWD="$(cat /run/secrets/db_password)" \
mariadb \
    --protocol=tcp \
    --host=127.0.0.1 \
    --port="$MARIADB_PORT" \
    --user="$MYSQL_USER" \
    --database="$MYSQL_DATABASE" \
    --execute="
        SELECT DATABASE() AS current_database;

        SELECT COUNT(*) AS wordpress_tables
        FROM information_schema.tables
        WHERE table_schema = DATABASE();
    "
'
```

Expected database:

```text
wordpress
```

The table count must be greater than zero.

A fresh WordPress installation may create a different number of tables depending on the installed version.

---

<a id="docker-network-and-dns"></a>
# 11. Docker Network and DNS

## 11.1 Inspect the project network

```bash
docker network inspect inception_inception \
    --format '{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{println}}{{end}}'
```

Expected containers:

```text
mariadb
wordpress
nginx
```

Container IP addresses and output order may differ.

---

## 11.2 Check Docker DNS

From WordPress:

```bash
docker exec wordpress getent hosts mariadb
```

Expected hostname:

```text
mariadb
```

From NGINX:

```bash
docker exec nginx getent hosts wordpress
```

Expected hostname:

```text
wordpress
```

This confirms the internal service path:

```text
Browser
→ NGINX:443
→ wordpress:9000
→ mariadb:3306
```

---

<a id="persistence-test"></a>
# 12. Persistence Test

This test confirms that WordPress files and MariaDB data survive container removal and recreation.

Do not use `make fclean` during this test.

## 12.1 Create a unique test identifier

```bash
TEST_ID="persistence-$(date +%Y%m%d-%H%M%S)"

printf '%s\n' "$TEST_ID" \
    | tee /tmp/inception-persistence-id
```

---

## 12.2 Create a file in the WordPress volume

```bash
docker exec -u www-data wordpress sh -c \
    "printf '%s\n' '$TEST_ID' \
    > '/var/www/html/wp-content/${TEST_ID}.txt'"
```

Check it inside the container:

```bash
docker exec wordpress \
    cat "/var/www/html/wp-content/${TEST_ID}.txt"
```

Check the same file on the VM:

```bash
sudo cat \
    "/home/tsargsya/data/wordpress/wp-content/${TEST_ID}.txt"
```

Both commands must print the same test identifier.

---

## 12.3 Create a draft post in MariaDB

```bash
POST_ID="$(
    docker exec -u www-data wordpress \
        wp --path=/var/www/html post create \
        --post_type=post \
        --post_status=draft \
        --post_title="$TEST_ID" \
        --porcelain
)"
```

Save the post ID:

```bash
printf '%s\n' "$POST_ID" \
    | tee /tmp/inception-persistence-post-id
```

Check the record:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html post get "$POST_ID" \
    --fields=ID,post_title,post_status \
    --format=table
```

Expected values:

```text
post_title  persistence-...
post_status draft
```

---

## 12.4 Inspect both named volumes

```bash
docker volume inspect mariadb_data \
    --format 'name={{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}} options={{json .Options}}'

docker volume inspect wordpress_data \
    --format 'name={{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}} options={{json .Options}}'
```

Expected host devices:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/wordpress
```

Optional size check:

```bash
sudo du -sh \
    /home/tsargsya/data/mariadb \
    /home/tsargsya/data/wordpress
```

---

## 12.5 Remove containers without deleting data

```bash
make down
```

Check that the containers were removed:

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

Expected result:

```text
Empty container table
```

Check that the volumes still exist:

```bash
docker volume ls \
    --format '{{.Name}}' \
    | grep -E '^(mariadb_data|wordpress_data)$'
```

Expected result:

```text
mariadb_data
wordpress_data
```

Restore shell variables when necessary:

```bash
TEST_ID="$(cat /tmp/inception-persistence-id)"
POST_ID="$(cat /tmp/inception-persistence-post-id)"
```

Check the host file:

```bash
sudo cat \
    "/home/tsargsya/data/wordpress/wp-content/${TEST_ID}.txt"
```

Check the database directory:

```bash
sudo test -d /home/tsargsya/data/mariadb/wordpress \
    && echo "PASS: MariaDB database directory persists" \
    || echo "FAIL: MariaDB database directory is missing"
```

---

## 12.6 Recreate the containers

```bash
time make
sleep 15
```

Check the state:

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

All three containers must be `Up`.

The existing certificate should be preserved.

The images should mostly use the Docker build cache.

---

## 12.7 Verify the preserved WordPress file

```bash
TEST_ID="$(cat /tmp/inception-persistence-id)"
POST_ID="$(cat /tmp/inception-persistence-post-id)"

docker exec wordpress \
    cat "/var/www/html/wp-content/${TEST_ID}.txt"
```

Expected result:

```text
The original test identifier
```

---

## 12.8 Verify the preserved database record

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html post get "$POST_ID" \
    --fields=ID,post_title,post_status \
    --format=table
```

The post ID, title, and draft state must be unchanged.

Check that the users are still present:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html user list \
    --fields=ID,user_login,roles \
    --format=table
```

Check the site:

```bash
curl -k -sS \
    -o /dev/null \
    -w 'HTTPS status=%{http_code}\n' \
    https://tsargsya.42.fr/
```

Expected result:

```text
HTTPS status=200
```

---

## 12.9 Confirm that initialization was not repeated

MariaDB:

```bash
docker compose -f srcs/docker-compose.yml \
    logs --no-color mariadb \
    | grep -E \
        'Initializing MariaDB|Configuring the Inception|initialization completed' \
    || echo "PASS: MariaDB initialization was not repeated"
```

Expected result:

```text
PASS: MariaDB initialization was not repeated
```

WordPress:

```bash
docker compose -f srcs/docker-compose.yml \
    logs --no-color wordpress
```

Expected messages:

```text
WordPress files already exist.
Waiting for MariaDB...
MariaDB is ready.
WordPress is already installed.
Second WordPress user already exists.
```

---

<a id="crash-restart-test"></a>
# 13. Crash Restart Test

The services use:

```text
restart: on-failure
```

The test must simulate an unexpected process crash.

Do not use:

```bash
docker stop
docker kill
```

for this acceptance test. These are manual Docker management actions and can suppress the automatic restart policy.

Instead, kill the container's host PID so that Docker observes the main process exiting unexpectedly.

Before testing, every container should have been running successfully for at least several seconds.

---

## 13.1 Check the configured restart policy

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format '{{.Name}} policy={{.HostConfig.RestartPolicy.Name}} maximum_retries={{.HostConfig.RestartPolicy.MaximumRetryCount}}' \
        "$container"
done
```

Expected policy:

```text
on-failure
```

A `maximum_retries` value of `0` means that no explicit retry limit was configured.

---

## 13.2 Define the crash-test function

This function is compatible with Zsh and avoids the reserved Zsh variable name `status`.

```bash
test_crash_restart()
{
    local container_name="$1"
    local restart_before
    local restart_after
    local host_pid
    local container_state
    local attempt

    restart_before="$(
        docker inspect \
            --format '{{.RestartCount}}' \
            "$container_name"
    )" || return 1

    host_pid="$(
        docker inspect \
            --format '{{.State.Pid}}' \
            "$container_name"
    )" || return 1

    if [ -z "$host_pid" ] || [ "$host_pid" -le 1 ]; then
        echo "FAIL: invalid host PID for $container_name: $host_pid"
        return 1
    fi

    echo
    echo "===== REAL CRASH TEST: $container_name ====="
    echo "Host PID: $host_pid"
    echo "Restart count before: $restart_before"

    sudo kill -KILL "$host_pid"

    attempt=0

    while [ "$attempt" -lt 30 ]
    do
        container_state="$(
            docker inspect \
                --format '{{.State.Status}}' \
                "$container_name"
        )"

        restart_after="$(
            docker inspect \
                --format '{{.RestartCount}}' \
                "$container_name"
        )"

        echo \
            "Attempt $attempt: state=$container_state restart_count=$restart_after"

        if [ "$container_state" = "running" ] \
            && [ "$restart_after" -gt "$restart_before" ]; then
            echo "PASS: $container_name restarted automatically"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 1
    done

    echo "FAIL: $container_name did not restart automatically"

    docker inspect \
        --format \
        'state={{.State.Status}} restart_count={{.RestartCount}} exit_code={{.State.ExitCode}} error={{.State.Error}}' \
        "$container_name"

    return 1
}
```

---

## 13.3 Test NGINX

```bash
test_crash_restart nginx
sleep 3
```

Check the state:

```bash
docker inspect \
    --format \
    'state={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}}' \
    nginx
```

Check HTTPS:

```bash
curl -k -sS \
    -o /dev/null \
    -w 'After real NGINX crash: HTTP %{http_code}\n' \
    https://tsargsya.42.fr/
```

Expected result:

```text
running=true
restart_count increased
HTTP 200
```

---

## 13.4 Test WordPress

```bash
test_crash_restart wordpress
sleep 5
```

Check the state:

```bash
docker inspect \
    --format \
    'state={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}}' \
    wordpress
```

Check WordPress:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html core is-installed \
    && echo "PASS: WordPress works after crash"
```

Check HTTPS:

```bash
curl -k -sS \
    -o /dev/null \
    -w 'After real WordPress crash: HTTP %{http_code}\n' \
    https://tsargsya.42.fr/
```

Expected result:

```text
running=true
restart_count increased
PASS: WordPress works after crash
HTTP 200
```

---

## 13.5 Test MariaDB

```bash
test_crash_restart mariadb
sleep 10
```

MariaDB may perform InnoDB crash recovery before it becomes ready.

Check the state:

```bash
docker inspect \
    --format \
    'state={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}}' \
    mariadb
```

Check the database:

```bash
docker exec mariadb sh -c '
MYSQL_PWD="$(cat /run/secrets/db_password)" \
mariadb \
    --protocol=tcp \
    --host=127.0.0.1 \
    --port="$MARIADB_PORT" \
    --user="$MYSQL_USER" \
    --database="$MYSQL_DATABASE" \
    --execute="
        SELECT 1 AS database_available;

        SELECT COUNT(*) AS wordpress_tables
        FROM information_schema.tables
        WHERE table_schema = DATABASE();
    "
'
```

Check WordPress:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html option get siteurl
```

Check HTTPS:

```bash
curl -k -sS \
    --retry 10 \
    --retry-delay 1 \
    --retry-connrefused \
    -o /dev/null \
    -w 'After real MariaDB crash: HTTP %{http_code}\n' \
    https://tsargsya.42.fr/
```

Expected result:

```text
database_available = 1
WordPress table count greater than zero
https://tsargsya.42.fr
HTTP 200
```

---

## 13.6 Check the final restart state

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format \
        '{{.Name}} state={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} exit_code={{.State.ExitCode}}' \
        "$container"
done
```

After one successful crash test per service, the expected state is:

```text
/mariadb   running=true restart_count=1
/wordpress running=true restart_count=1
/nginx     running=true restart_count=1
```

A different positive restart count is acceptable when a service was tested more than once.

---

<a id="git-and-security-audit"></a>
# 14. Git and Security Audit

## 14.1 Check the final Git state

```bash
git status --short
git log -1 --oneline
```

Expected working tree:

```text
No output from git status --short
```

---

## 14.2 Check tracked secret and certificate paths

```bash
git ls-files secrets certificates
```

Allowed tracked files:

```text
certificates/.gitkeep
secrets/.gitkeep
```

The following files must not be tracked:

```text
secrets/*.txt
certificates/inception.crt
certificates/inception.key
```

---

## 14.3 Check `.gitignore`

```bash
git check-ignore -v \
    secrets/db_root_password.txt \
    secrets/db_password.txt \
    secrets/wp_admin_password.txt \
    secrets/wp_user_password.txt \
    certificates/inception.crt \
    certificates/inception.key
```

Every file must match an ignore rule.

---

## 14.4 Check Git history for secret file paths

```bash
git rev-list --objects --all \
    | grep -E \
        '(^| )(secrets/.*\.txt|certificates/.*\.key|credentials\.txt)$' \
    || echo "PASS: no secret files or private keys found in Git history"
```

Expected result:

```text
PASS: no secret files or private keys found in Git history
```

Additional path check:

```bash
git log --all \
    --format= \
    --name-only \
    -- \
    secrets/db_root_password.txt \
    secrets/db_password.txt \
    secrets/wp_admin_password.txt \
    secrets/wp_user_password.txt \
    certificates/inception.key \
    | sed '/^$/d' \
    | sort -u
```

Expected result:

```text
No output
```

---

## 14.5 Check that current secret values are absent from tracked files

This command does not print the secret values:

```bash
for secret_file in secrets/*.txt
do
    secret_value="$(tr -d '\r\n' < "$secret_file")"

    if [ -z "$secret_value" ]; then
        echo "FAIL: $secret_file is empty"
    elif git grep -F -q -e "$secret_value" --; then
        echo "FAIL: value from $secret_file exists in a tracked file"
    else
        echo "PASS: value from $secret_file is absent from tracked files"
    fi
done

unset secret_value
```

Expected result:

```text
PASS for all four secret files
```

---

## 14.6 Search for forbidden container hacks

```bash
grep -RInE \
    'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+(true|:)|network_mode:[[:space:]]*host|^[[:space:]]*links:' \
    srcs \
    || echo "PASS: no forbidden container hacks found"
```

Expected result:

```text
PASS: no forbidden container hacks found
```

---

## 14.7 Check for the `latest` tag

```bash
grep -RInE \
    'FROM[[:space:]]+[^[:space:]]*:latest|image:[[:space:]]*[^[:space:]]*:latest' \
    srcs \
    || echo "PASS: no latest tags found"
```

Expected result:

```text
PASS: no latest tags found
```

---

## 14.8 Check base images

```bash
find srcs/requirements \
    -name Dockerfile \
    -exec grep -H '^FROM ' {} +
```

Expected base:

```text
FROM debian:bookworm
```

The project must not use ready-made service images as Dockerfile bases:

```text
FROM nginx:...
FROM wordpress:...
FROM mariadb:...
```

---

## 14.9 Recheck the resolved architecture

```bash
echo
echo "===== COMPOSE SERVICES ====="
docker compose -f srcs/docker-compose.yml config --services

echo
echo "===== COMPOSE IMAGES ====="
docker compose -f srcs/docker-compose.yml config --images

echo
echo "===== COMPOSE VOLUMES ====="
docker compose -f srcs/docker-compose.yml config --volumes

echo
echo "===== COMPOSE NETWORKS ====="
docker compose -f srcs/docker-compose.yml config --networks
```

Expected architecture:

```text
Services:
mariadb
wordpress
nginx

Images:
mariadb:inception
wordpress:inception
nginx:inception

Volumes:
mariadb_data
wordpress_data

Network:
inception
```

Check port bindings one final time:

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format \
        '{{.Name}} PortBindings={{json .HostConfig.PortBindings}}' \
        "$container"
done
```

Expected result:

```text
/mariadb PortBindings={}
/wordpress PortBindings={}
/nginx PortBindings={"443/tcp":[...]}
```

---

<a id="remove-persistence-test-data"></a>
# 15. Remove Persistence-Test Data

Restore the saved identifiers:

```bash
TEST_ID="$(cat /tmp/inception-persistence-id)"
POST_ID="$(cat /tmp/inception-persistence-post-id)"
```

Remove the draft post:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html \
    post delete "$POST_ID" --force
```

Remove the volume test file:

```bash
docker exec -u www-data wordpress \
    rm -f "/var/www/html/wp-content/${TEST_ID}.txt"
```

Confirm file removal:

```bash
if docker exec wordpress \
    test -e "/var/www/html/wp-content/${TEST_ID}.txt"
then
    echo "FAIL: persistence test file still exists"
else
    echo "PASS: persistence test file removed"
fi
```

Confirm post removal:

```bash
if docker exec -u www-data wordpress \
    wp --path=/var/www/html \
    post get "$POST_ID" >/dev/null 2>&1
then
    echo "FAIL: persistence test post still exists"
else
    echo "PASS: persistence test post removed"
fi
```

Remove temporary host files:

```bash
rm -f \
    /tmp/inception-persistence-id \
    /tmp/inception-persistence-post-id

unset TEST_ID
unset POST_ID
```

---

<a id="final-acceptance-check"></a>
# 16. Final Acceptance Check

## 16.1 Final container state

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

Expected state:

```text
mariadb     Up
wordpress   Up
nginx       Up
```

Check restart policy and state:

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format \
        '{{.Name}} state={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} policy={{.HostConfig.RestartPolicy.Name}}' \
        "$container"
done
```

Expected values:

```text
state=running
running=true
restart_count greater than or equal to 1
policy=on-failure
```

---

## 16.2 Final HTTPS test

```bash
curl -k -sS \
    -o /dev/null \
    -w 'FINAL HTTPS status=%{http_code}\n' \
    https://tsargsya.42.fr/
```

Expected result:

```text
FINAL HTTPS status=200
```

---

## 16.3 Final Git state

```bash
git status --short
```

Expected result:

```text
No output
```

---

<a id="mandatory-acceptance-checklist"></a>
# Mandatory Acceptance Checklist

The mandatory part passes when all statements below are true.

## Infrastructure

- [ ] The project builds through the root `Makefile`.
- [ ] Three custom images are built from project Dockerfiles.
- [ ] The images use `debian:bookworm`, not ready-made service images.
- [ ] MariaDB, WordPress, and NGINX run in separate containers.
- [ ] All containers use `restart: on-failure`.
- [ ] The real service process runs as PID 1.
- [ ] No forbidden infinite-process hack is used.

## Network and ports

- [ ] All three services are connected to the project bridge network.
- [ ] Docker DNS resolves `mariadb` and `wordpress`.
- [ ] Only NGINX publishes a host port.
- [ ] Port `443` is published.
- [ ] Port `80` is closed.
- [ ] MariaDB port `3306` remains internal.
- [ ] PHP-FPM port `9000` remains internal.

## TLS and domain

- [ ] `tsargsya.42.fr` resolves to `127.0.0.1`.
- [ ] The certificate contains `tsargsya.42.fr`.
- [ ] The certificate and key have appropriate permissions.
- [ ] TLS 1.2 works.
- [ ] TLS 1.3 works.
- [ ] TLS 1.0 is rejected.
- [ ] TLS 1.1 is rejected.
- [ ] HTTPS returns status `200`.

## WordPress

- [ ] WordPress is installed.
- [ ] `siteurl` and `home` use `https://tsargsya.42.fr`.
- [ ] The site title is `Inception`.
- [ ] The administrator user exists.
- [ ] The administrator username does not contain `admin`.
- [ ] A second non-administrator user exists.
- [ ] PHP-FPM serves WordPress through NGINX.

## MariaDB

- [ ] The `wordpress` database exists.
- [ ] The `wpuser` account exists.
- [ ] The application account can connect through TCP.
- [ ] WordPress tables exist.
- [ ] MariaDB data is stored in `/home/tsargsya/data/mariadb`.

## Volumes and persistence

- [ ] `mariadb_data` exists.
- [ ] `wordpress_data` exists.
- [ ] WordPress files are stored in `/home/tsargsya/data/wordpress`.
- [ ] WordPress files survive `make down` and container recreation.
- [ ] MariaDB records survive `make down` and container recreation.
- [ ] MariaDB initialization is not repeated with preserved data.
- [ ] WordPress installation is not repeated with preserved data.

## Restart behavior

- [ ] NGINX automatically restarts after its main process crashes.
- [ ] WordPress automatically restarts after its main process crashes.
- [ ] MariaDB automatically restarts after its main process crashes.
- [ ] The website works after every service recovery.
- [ ] Persistent data remains intact after crash recovery.

## Secrets and Git

- [ ] Secret source files exist locally and are not empty.
- [ ] Secret source files have mode `600`.
- [ ] Secret files are ignored by Git.
- [ ] The private TLS key is ignored by Git.
- [ ] No secret file path exists in Git history.
- [ ] Current secret values do not exist in tracked files.
- [ ] No `latest` image tag is used.
- [ ] The Git working tree is clean after the test.

---

<a id="validated-baseline"></a>
# Validated Baseline

A complete test run performed on `2026-08-02` produced the following result:

```text
Cold start:                 PASS
MariaDB initialization:    PASS
WordPress installation:    PASS
NGINX configuration:       PASS
HTTPS status:               200
Published host ports:       443 only
TLS 1.2:                    PASS
TLS 1.3:                    PASS
TLS 1.0 rejection:          PASS
TLS 1.1 rejection:          PASS
WordPress administrator:    tsargsya
WordPress second user:      writer
MariaDB application user:   wpuser
WordPress tables:           12
Docker DNS:                 PASS
WordPress persistence:      PASS
MariaDB persistence:        PASS
NGINX crash restart:        PASS
WordPress crash restart:    PASS
MariaDB crash restart:      PASS
Secret Git audit:           PASS
Final HTTPS status:         200
Final Git state:            clean
```

The exact WordPress version and number of tables may change in future runs, but installation, connectivity, persistence, and service behavior must continue to pass.

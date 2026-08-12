# Inception Evaluation Guide

This file is a linear defense runbook for the Inception project.

It is intentionally shorter than the service-specific documentation. Use it during an evaluation to remember **what to show, which command to run, and what result is expected**. You do not need to memorize the long commands.

Run commands from the repository root unless stated otherwise.

For deeper explanations and troubleshooting, use:

```text
README.md
USER_DOC.md
DEV_DOC.md
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

---

# 0. Before the evaluation

Open this guide in a second terminal or editor:

```bash
less EVALUATION_GUIDE.md
```

Useful shell shortcuts:

```text
Ctrl+R     search shell history
q          leave less
/word      search inside less
n          next search result
```

Do not expose passwords in Git commits, screenshots, copied logs, or documentation. When a browser login is required, read the corresponding local secret only when necessary.

---

# 1. Preliminary repository checks

## 1.1 Confirm the evaluated revision

```bash
git branch --show-current
git status --short
git log -1 --oneline
```

Expected:

```text
branch: main
working tree: clean
```

## 1.2 Show the project structure

```bash
tree -a -L 4
```

Important files:

```text
Makefile
README.md
USER_DOC.md
DEV_DOC.md
srcs/docker-compose.yml
srcs/.env
srcs/requirements/...
```

## 1.3 README and required documentation

```bash
head -n 1 README.md
ls -l README.md USER_DOC.md DEV_DOC.md
```

Expected README first line:

```text
*This project has been created as part of the 42 curriculum by tsargsya.*
```

The README contains the required comparisons:

```text
Virtual Machines vs Docker
Secrets vs Environment Variables
Docker Network vs Host Network
Docker Volumes vs Bind Mounts
```

---

# 2. Secrets and Git security

## 2.1 Check tracked secret paths

```bash
git ls-files secrets certificates
```

Allowed tracked files:

```text
secrets/.gitkeep
certificates/.gitkeep
```

Secret `.txt` files and `certificates/inception.key` must not be tracked.

## 2.2 Check Git history for secret files

```bash
git rev-list --objects --all \
    | grep -E '(^| )(secrets/.*\.txt|certificates/.*\.key|credentials\.txt)$' \
    || echo 'PASS: no secret files or private keys found in Git history'
```

Expected:

```text
PASS: no secret files or private keys found in Git history
```

## 2.3 Generate local secrets when necessary

```bash
python3 srcs/tools/generate_secrets.py
```

Check existence and permissions without displaying values:

```bash
stat -c '%a %n' secrets/*.txt
```

Expected mode:

```text
600
```

---

# 3. Clean start and build

> Warning: `make fclean` removes the WordPress and MariaDB persistent data under `/home/tsargsya/data`.

For a clean project reset:

```bash
make fclean
```

If the evaluator performs the global Docker cleanup from the evaluation sheet, let that procedure finish first. For a true cold start also ensure the old project host data is gone:

```bash
sudo rm -rf /home/tsargsya/data
```

Generate secrets if this is a fresh clone:

```bash
python3 srcs/tools/generate_secrets.py
```

Build and start the complete project through the Makefile:

```bash
make
```

Check the stack:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected services:

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

All must be `Up`.

---

# 4. Compose, images, Dockerfiles, and forbidden patterns

## 4.1 Show resolved Compose resources

```bash
docker compose -f srcs/docker-compose.yml config --services
docker compose -f srcs/docker-compose.yml config --images
docker compose -f srcs/docker-compose.yml config --volumes
docker compose -f srcs/docker-compose.yml config --networks
```

Important mandatory resources:

```text
services: mariadb wordpress nginx
images:   mariadb:inception wordpress:inception nginx:inception
volumes:  mariadb_data wordpress_data
network:  inception
```

## 4.2 Show the base images

```bash
find srcs/requirements -name Dockerfile -maxdepth 2 \
    -exec grep -H '^FROM ' {} \;
```

Expected current base:

```text
debian:bookworm
```

No project service uses a ready-made service image.

## 4.3 Check for `latest`

```bash
grep -RInE 'FROM[[:space:]].*:latest|image:[[:space:]].*:latest' srcs \
    || echo 'PASS: no latest tag'
```

## 4.4 Check forbidden container keep-alive/network hacks

```bash
grep -RInE \
    'tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+true|network_mode:[[:space:]]*host|--link|^[[:space:]]*links:' \
    srcs/requirements srcs/docker-compose.yml \
    || echo 'PASS: no forbidden keep-alive or host-network/link pattern'
```

Expected: PASS and no matching project configuration.

---

# 5. PID 1 and restart policy

Show the mandatory main processes:

```bash
for container in mariadb wordpress nginx
do
    echo "===== $container ====="
    docker exec "$container" sh -c \
        'printf "PID 1: "; tr "\000" " " </proc/1/cmdline; echo'
done
```

Expected main applications:

```text
mariadb   -> mariadbd
wordpress -> php-fpm8.2 -F
nginx     -> nginx -g daemon off;
```

Check restart policy:

```bash
for container in mariadb wordpress nginx
do
    docker inspect \
        --format '{{.Name}} policy={{.HostConfig.RestartPolicy.Name}} restart_count={{.RestartCount}}' \
        "$container"
done
```

Expected:

```text
policy=on-failure
```

For the full real-crash test, use the dedicated section in:

```text
docs/mandatory-testing.md
```

---

# 6. Docker network, DNS, and published ports

## 6.1 Inspect the project network

```bash
docker network inspect inception_inception \
    --format '{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{println}}{{end}}'
```

The mandatory containers must be present; bonus containers may also be present.

## 6.2 Docker DNS

```bash
docker exec wordpress getent hosts mariadb
docker exec nginx getent hosts wordpress
docker exec wordpress getent hosts redis
```

Expected: each service name resolves to a Docker-network IP.

## 6.3 Published ports

```bash
docker compose -f srcs/docker-compose.yml ps
```

Mandatory external entrypoint:

```text
NGINX -> host port 443
```

Internal mandatory ports:

```text
MariaDB   3306
WordPress 9000
```

Bonus FTP is allowed to publish its own required ports:

```text
21
21000-21010
```

Check mandatory mappings directly:

```bash
docker port mariadb
docker port wordpress
docker port nginx
```

Expected:

```text
mariadb:   no host mapping
wordpress: no host mapping
nginx:     443 host mapping
```

---

# 7. NGINX, HTTPS, port 80, and TLS

## 7.1 NGINX configuration

```bash
docker exec nginx nginx -t
```

Expected:

```text
syntax is ok
test is successful
```

Show PID/process if requested:

```bash
docker top nginx
```

## 7.2 HTTPS works

```bash
curl -k -o /dev/null -s -w 'HTTPS %{http_code}\n' \
    https://tsargsya.42.fr/
```

Expected:

```text
HTTPS 200
```

## 7.3 HTTP port 80 is unavailable

```bash
if curl -4 -sS --connect-timeout 3 -o /dev/null \
    http://tsargsya.42.fr/ 2>/dev/null
then
    echo 'FAIL: HTTP port 80 is reachable'
else
    echo 'PASS: HTTP port 80 is unavailable'
fi
```

Expected:

```text
PASS: HTTP port 80 is unavailable
```

## 7.4 TLS 1.2

```bash
openssl s_client \
    -brief \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1_2 \
    </dev/null 2>&1 \
    | grep 'Protocol version'
```

Expected:

```text
Protocol version: TLSv1.2
```

## 7.5 TLS 1.3

```bash
openssl s_client \
    -brief \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1_3 \
    </dev/null 2>&1 \
    | grep 'Protocol version'
```

Expected:

```text
Protocol version: TLSv1.3
```

## 7.6 TLS 1.0 and 1.1 are rejected

TLS 1.0:

```bash
openssl s_client \
    -brief \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1 \
    -cipher 'DEFAULT:@SECLEVEL=0' \
    </dev/null
```

TLS 1.1:

```bash
openssl s_client \
    -brief \
    -connect tsargsya.42.fr:443 \
    -servername tsargsya.42.fr \
    -tls1_1 \
    -cipher 'DEFAULT:@SECLEVEL=0' \
    </dev/null
```

Expected: connection failure / protocol-version alert.

---

# 8. WordPress mandatory browser test

## 8.1 Confirm installation from the CLI

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html core is-installed \
    && echo 'PASS: WordPress installed'
```

List the users:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html user list \
    --fields=ID,user_login,roles \
    --format=table
```

Expected users:

```text
tsargsya -> administrator
writer   -> author
```

The administrator username must not contain `admin` or `administrator`.

## 8.2 Browser: normal user

Open:

```text
https://tsargsya.42.fr/wp-admin
```

Login:

```text
username: writer
password: secrets/wp_user_password.txt
```

If you need to read the local password:

```bash
cat secrets/wp_user_password.txt
```

Then:

```text
1. Open a post.
2. Add a harmless evaluation comment.
3. Confirm that the comment appears.
```

## 8.3 Browser: administrator

Logout from `writer`, then login as:

```text
username: tsargsya
password: secrets/wp_admin_password.txt
```

If needed:

```bash
cat secrets/wp_admin_password.txt
```

Then:

```text
1. Open an existing page.
2. Add a visible harmless marker such as INCEPTION EVALUATION TEST.
3. Click Update.
4. Open the public page.
5. Confirm that the new content is visible.
```

This proves the complete flow:

```text
Browser -> NGINX -> WordPress/PHP-FPM -> MariaDB
```

---

# 9. MariaDB mandatory test

## 9.1 Database and users

This command reads the secret inside the container and does not print the password:

```bash
docker exec mariadb sh -c '
MYSQL_PWD="$(cat /run/secrets/db_root_password)" \
mariadb \
    --protocol=socket \
    --socket=/run/mysqld/mysqld.sock \
    --user=root \
    --execute="
        SHOW DATABASES;
        SELECT User, Host FROM mysql.user ORDER BY User, Host;
    "
'
```

Expected:

```text
wordpress database
wpuser @ %
```

## 9.2 Confirm that the WordPress database is not empty

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

Expected:

```text
current_database = wordpress
wordpress_tables > 0
```

---

# 10. Named volumes and host persistence paths

Inspect both Docker volume objects:

```bash
docker volume inspect mariadb_data
docker volume inspect wordpress_data
```

Expected host devices include:

```text
/home/tsargsya/data/mariadb
/home/tsargsya/data/wordpress
```

Inspect container mounts:

```bash
docker inspect mariadb \
    --format '{{range .Mounts}}{{println .Type .Name .Source "->" .Destination}}{{end}}'

docker inspect wordpress \
    --format '{{range .Mounts}}{{println .Type .Name .Source "->" .Destination}}{{end}}'
```

Expected destinations:

```text
mariadb_data   -> /var/lib/mysql
wordpress_data -> /var/www/html
```

Check the host data:

```bash
sudo ls -la /home/tsargsya/data/mariadb | head
sudo ls -la /home/tsargsya/data/wordpress | head
```

---

# 11. Persistence across a VM reboot

Use a visible WordPress edit as the persistence marker. For example, keep the harmless page text added during the administrator test.

Before reboot, confirm that the marker is visible in the browser.

Reboot the VM:

```bash
sudo reboot
```

After the VM starts again:

```bash
cd /home/tsargsya/inception
make
```

Check the stack:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Then open:

```text
https://tsargsya.42.fr
```

Expected:

```text
The WordPress site is still configured.
The previous page edit still exists.
Users/comments/content remain present.
```

This proves that the WordPress files and MariaDB data survived a VM reboot and container recreation.

---

# 12. Configuration modification test

The evaluator may ask for a small configuration change. A rehearsed example is changing the **internal MariaDB port**.

Current values:

```bash
grep -n 'MARIADB_PORT' srcs/environment/database.env
grep -n '^port' srcs/requirements/mariadb/conf/99-inception.cnf
grep -n '^EXPOSE' srcs/requirements/mariadb/Dockerfile
```

Example change:

```text
3306 -> 3307
```

Update these values consistently:

```text
srcs/environment/database.env
    MARIADB_PORT=3307

srcs/requirements/mariadb/conf/99-inception.cnf
    port=3307

srcs/requirements/mariadb/Dockerfile
    EXPOSE 3307
```

Rebuild while preserving data:

```bash
make rebuild
```

Check the new WordPress DB host:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html config get DB_HOST
```

Expected:

```text
mariadb:3307
```

Check MariaDB's runtime port:

```bash
docker exec mariadb sh -c '
MYSQL_PWD="$(cat /run/secrets/db_root_password)" \
mariadb \
    --protocol=socket \
    --socket=/run/mysqld/mysqld.sock \
    --user=root \
    --execute="SHOW VARIABLES LIKE '\''port'\'';"
'
```

Expected port:

```text
3307
```

Check the website:

```bash
curl -k -o /dev/null -s -w 'HTTP %{http_code}\n' \
    https://tsargsya.42.fr/
```

Expected:

```text
HTTP 200
```

If the evaluator wants the original configuration restored, change `3307` back to `3306` in the same three places and run:

```bash
make rebuild
```

---

# 13. Bonus 1/5 — Redis object cache

## 13.1 Redis server

```bash
docker exec redis redis-cli ping
```

Expected:

```text
PONG
```

## 13.2 WordPress Redis integration

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html redis status
```

Important expected values:

```text
Status: Connected
Client: PhpRedis
Drop-in: Valid
Disabled: No
Errors: []
WP_REDIS_HOST: redis
WP_REDIS_PORT: 6379
```

Plugin status:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html plugin status redis-cache
```

Expected:

```text
Status: Active
```

Generate normal site traffic:

```bash
curl -k -s https://tsargsya.42.fr/ >/dev/null
curl -k -s https://tsargsya.42.fr/ >/dev/null
```

Check Redis keys:

```bash
docker exec redis redis-cli DBSIZE
docker exec redis redis-cli --scan | head
```

Expected: non-zero cache size and WordPress-related keys.

---

# 14. Bonus 2/5 — FTP to the WordPress volume

Check the service:

```bash
docker compose -f srcs/docker-compose.yml ps ftp
docker logs ftp --tail 50
```

Prepare a harmless test file:

```bash
echo "Inception FTP evaluation test $(date)" \
    > /tmp/inception_ftp_test.txt
```

Load the password into a shell variable without typing it into the command history:

```bash
FTP_PASSWORD="$(cat secrets/ftp_password.txt)"
```

Upload through passive FTP:

```bash
curl --ftp-pasv \
    --user "ftpuser:$FTP_PASSWORD" \
    -T /tmp/inception_ftp_test.txt \
    ftp://127.0.0.1/inception_ftp_test.txt
```

Expected exit code:

```bash
echo $?
```

```text
0
```

List the FTP root:

```bash
curl --ftp-pasv \
    --user "ftpuser:$FTP_PASSWORD" \
    ftp://127.0.0.1/
```

Expected: WordPress files plus `inception_ftp_test.txt`.

Prove that WordPress sees the same uploaded file:

```bash
docker exec wordpress \
    cat /var/www/html/inception_ftp_test.txt
```

Download it back:

```bash
rm -f /tmp/inception_ftp_downloaded.txt

curl --ftp-pasv \
    --user "ftpuser:$FTP_PASSWORD" \
    ftp://127.0.0.1/inception_ftp_test.txt \
    -o /tmp/inception_ftp_downloaded.txt
```

Compare byte-for-byte:

```bash
cmp /tmp/inception_ftp_test.txt /tmp/inception_ftp_downloaded.txt \
    && echo 'FTP upload/download: OK'
```

Expected:

```text
FTP upload/download: OK
```

Clean the test file from FTP:

```bash
curl --ftp-pasv \
    --user "ftpuser:$FTP_PASSWORD" \
    -Q 'DELE inception_ftp_test.txt' \
    ftp://127.0.0.1/
```

Confirm removal from WordPress:

```bash
docker exec wordpress \
    test ! -e /var/www/html/inception_ftp_test.txt \
    && echo 'FTP test file removed'
```

---

# 15. Bonus 3/5 — Static website

Check the container and real process:

```bash
docker compose -f srcs/docker-compose.yml ps static_site
docker top static_site
```

Expected process:

```text
python3 -m http.server 8080 --bind 0.0.0.0 --directory /var/www/static
```

Check the website:

```bash
curl -k -o /dev/null -s -w 'HTTP %{http_code}\n' \
    https://portfolio.tsargsya.42.fr/
```

Expected:

```text
HTTP 200
```

Show the HTML title:

```bash
curl -k -s https://portfolio.tsargsya.42.fr/ \
    | grep -i '<title'
```

Confirm that no PHP source exists:

```bash
find srcs/requirements/static_site/website \
    -type f -name '*.php' -print
```

Expected: no output.

Confirm PHP is not installed in the static-site container:

```bash
docker exec static_site sh -c '
if command -v php >/dev/null 2>&1; then
    echo "PHP FOUND"
    exit 1
else
    echo "PHP NOT INSTALLED"
fi
'
```

Expected:

```text
PHP NOT INSTALLED
```

Check assets:

```bash
curl -k -o /dev/null -s -w 'CSS %{http_code}\n' \
    https://portfolio.tsargsya.42.fr/style.css

curl -k -o /dev/null -s -w 'JS %{http_code}\n' \
    https://portfolio.tsargsya.42.fr/script.js
```

Expected:

```text
CSS 200
JS 200
```

Also open the site in a browser and show that the CSS/JavaScript UI works.

---

# 16. Bonus 4/5 — Adminer

Check the container and PHP-FPM process:

```bash
docker compose -f srcs/docker-compose.yml ps adminer
docker top adminer
```

Check HTTPS:

```bash
curl -k -o /dev/null -s -w 'HTTP %{http_code}\n' \
    https://adminer.tsargsya.42.fr/
```

Expected:

```text
HTTP 200
```

Confirm that port `9000` is not published to the host:

```bash
docker port adminer
```

Expected: no output.

Detailed port state:

```bash
docker inspect \
    --format '{{json .NetworkSettings.Ports}}' \
    adminer
```

Expected:

```text
{"9000/tcp":null}
```

Browser test:

```text
URL:      https://adminer.tsargsya.42.fr
System:   MySQL / MariaDB
Server:   mariadb
Username: wpuser
Password: secrets/db_password.txt
Database: wordpress
```

After login:

```text
1. Show the WordPress tables.
2. Open SQL command.
3. Run a read-only query.
```

Useful query:

```sql
SELECT ID, user_login
FROM wp_users
ORDER BY ID;
```

Expected users include:

```text
tsargsya
writer
```

---

# 17. Bonus 5/5 — Dockpeek

Check the container and Gunicorn process:

```bash
docker compose -f srcs/docker-compose.yml ps dockpeek
docker top dockpeek
```

Check the unauthenticated HTTPS response:

```bash
curl -k -I https://dockpeek.tsargsya.42.fr/
```

Expected:

```text
HTTP/1.1 302 FOUND
Location: /login
```

Inspect mounts and read-only state:

```bash
docker inspect dockpeek \
    --format '{{range .Mounts}}{{println .Source "->" .Destination "RW=" .RW}}{{end}}'
```

Important expected mount:

```text
/var/run/docker.sock -> /var/run/docker.sock RW= false
```

Check the socket inside the container:

```bash
docker exec dockpeek ls -l /var/run/docker.sock
```

Confirm that `8000` is not published to the host:

```bash
docker port dockpeek
```

Expected: no output.

Browser test:

```text
URL:      https://dockpeek.tsargsya.42.fr
Username: dockpeek
Password: secrets/dockpeek_password.txt
```

After login show that the dashboard contains the current containers:

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

Open one container and show real container information or logs. This proves that Dockpeek is using the Docker API rather than displaying static data.

Optional CLI proof of Docker API access:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/python \
    -c '
import docker
print([container.name for container in docker.from_env().containers.list()])
'
```

---

# 18. Final project state

Check all services one last time:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Check the main HTTPS site:

```bash
curl -k -o /dev/null -s -w 'WordPress: %{http_code}\n' \
    https://tsargsya.42.fr/
```

Check bonus web endpoints:

```bash
curl -k -o /dev/null -s -w 'Adminer: %{http_code}\n' \
    https://adminer.tsargsya.42.fr/

curl -k -o /dev/null -s -w 'Portfolio: %{http_code}\n' \
    https://portfolio.tsargsya.42.fr/

curl -k -o /dev/null -s -w 'Dockpeek: %{http_code}\n' \
    https://dockpeek.tsargsya.42.fr/
```

Expected normal values:

```text
WordPress: 200
Adminer:   200
Portfolio: 200
Dockpeek:  302   (unauthenticated redirect to /login)
```

Redis:

```bash
docker exec redis redis-cli ping
```

Expected:

```text
PONG
```

---

# 19. What to remember instead of memorizing commands

Remember the **tool for the question**, not every flag:

```text
What is running?             -> docker compose ps / docker ps
Why did it fail?             -> docker logs
What process is inside?      -> docker top / docker exec
How is a container configured? -> docker inspect
Where is persistent data?    -> docker volume inspect
How are containers connected? -> docker network inspect
Does Docker DNS work?        -> getent hosts <service>
Does HTTPS work?             -> curl
Which TLS version works?     -> openssl s_client
Does Redis work?             -> redis-cli ping / wp redis status
Does MariaDB contain data?   -> mariadb client / SQL
Does FTP share WP files?     -> FTP upload + docker exec wordpress
```

The evaluator is checking that you understand **why** each test proves something. Exact long `--format` expressions can be read from this guide.

---

# 20. Detailed references

If a test fails, move from this runbook to the detailed guide for that component:

```text
Mandatory end-to-end: docs/mandatory-testing.md
NGINX:               docs/nginx.md
WordPress:           docs/wordpress.md
MariaDB:             docs/mariadb.md
Redis:               docs/redis.md
FTP:                 docs/ftp.md
Static site:         docs/static_site.md
Adminer:             docs/adminer.md
Dockpeek:             docs/dockpeek.md
```

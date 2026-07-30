# WordPress Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container → Logs → Process → PHP-FPM → Files → Configuration → MariaDB → WordPress → Users → Volume
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
wordpress   Up
```

Useful states:

- `Up` — the container's main process is running.
- `Restarting` — the entrypoint or PHP-FPM repeatedly exits with an error.
- `Exited (1)` — the container stopped with an error.
- `Exited (0)` — the container stopped normally.

Important:

> `Up` means that the main process is running. It does not necessarily mean that WordPress can connect to MariaDB or serve a valid website.

---

## 2. Read the WordPress logs

```bash
docker logs wordpress
```

Show only the last 100 lines:

```bash
docker logs --tail=100 wordpress
```

Follow logs in real time:

```bash
docker logs -f wordpress
```

During a fresh installation, expected messages include:

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

During a normal restart with preserved data:

```text
WordPress files already exist.
Waiting for MariaDB...
MariaDB is ready.
WordPress is already installed.
Second WordPress user already exists.
```

Common error categories:

- missing environment variable;
- missing or empty secret;
- invalid administrator username;
- MariaDB connection timeout;
- MariaDB authentication failure;
- incorrect database host or port;
- permission denied in `/var/www/html`;
- WP-CLI failure;
- invalid PHP-FPM configuration;
- PHP-FPM startup failure.

Stop live log output with:

```text
Ctrl + C
```

---

## 3. Check the main process

Show the command running as PID 1:

```bash
docker exec wordpress sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'
```

Expected result:

```text
PID 1: php-fpm8.2 -F
```

The entrypoint prepares WordPress and then finishes with:

```sh
exec "$@"
```

The Dockerfile provides the default command:

```dockerfile
CMD ["php-fpm8.2", "-F"]
```

Therefore, PHP-FPM replaces the entrypoint process and becomes PID 1.

Inspect all WordPress container processes:

```bash
docker top wordpress
```

Expected process types:

```text
php-fpm: master process
php-fpm: pool www
```

---

## 4. Validate the PHP-FPM configuration

Run the PHP-FPM configuration test:

```bash
docker exec wordpress php-fpm8.2 -t
```

Expected result:

```text
configuration file ... test is successful
```

Inspect the important pool settings:

```bash
docker exec wordpress sh -c '
    grep -E "^(user|group|listen|pm|clear_env|catch_workers_output|decorate_workers_output)" \
        /etc/php/8.2/fpm/pool.d/www.conf
'
```

Expected values:

```ini
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
- worker output is forwarded to the container logs.

---

## 5. Check the PHP-FPM port

Inspect the port declared by the image:

```bash
docker inspect wordpress \
    --format '{{json .Config.ExposedPorts}}'
```

Expected result:

```text
{"9000/tcp":{}}
```

Check whether the port is published on the VM:

```bash
docker port wordpress
```

Expected result:

```text
No output
```

This is intentional.

Port `9000` is used internally:

```text
NGINX → FastCGI → wordpress:9000
```

It must not be exposed directly to the browser because PHP-FPM speaks FastCGI, not HTTP or HTTPS.

Important:

> `EXPOSE 9000` documents the internal application port. It does not publish the port on the host.

---

## 6. Check the WordPress files

List the main WordPress files:

```bash
docker exec wordpress sh -c '
    ls -ld \
        /var/www/html \
        /var/www/html/wp-admin \
        /var/www/html/wp-content \
        /var/www/html/wp-includes \
        /var/www/html/wp-load.php \
        /var/www/html/wp-config.php
'
```

Expected important paths:

```text
/var/www/html/wp-admin
/var/www/html/wp-content
/var/www/html/wp-includes
/var/www/html/wp-load.php
/var/www/html/wp-config.php
```

Meaning:

```text
wp-load.php exists
→ WordPress core files were downloaded

wp-config.php exists
→ database connection configuration was created
```

The entrypoint uses these files to decide whether an initialization step must be skipped.

---

## 7. Check file ownership

Check the owner and group:

```bash
docker exec wordpress stat \
    -c '%U:%G %a %n' \
    /var/www/html \
    /var/www/html/wp-load.php \
    /var/www/html/wp-config.php \
    /var/www/html/wp-content
```

Expected owner:

```text
www-data:www-data
```

WordPress files should be writable by the same Linux user that runs:

- PHP-FPM workers;
- WP-CLI commands.

Incorrect ownership such as:

```text
root:root
```

may prevent WordPress from:

- creating uploads;
- updating files;
- managing themes;
- managing plugins;
- writing cache files.

Do not solve permission problems with:

```bash
chmod -R 777
```

Correct the owner and required permissions instead.

---

## 8. Check WP-CLI

Show WP-CLI information:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html --info
```

Check the downloaded WordPress version:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html core version
```

Successful execution confirms that:

- WP-CLI exists;
- it is executable;
- the WordPress path is correct;
- `www-data` can access the files.

WP-CLI should normally run as:

```text
www-data
```

Do not run routine WordPress commands as root unless there is a specific reason.

---

## 9. Check `wp-config.php`

Confirm that the configuration file exists:

```bash
docker exec wordpress test -f /var/www/html/wp-config.php \
    && echo "wp-config.php exists"
```

Read only non-secret database settings:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html config get DB_NAME

docker exec -u www-data wordpress \
    wp --path=/var/www/html config get DB_USER

docker exec -u www-data wordpress \
    wp --path=/var/www/html config get DB_HOST
```

Expected values:

```text
DB_NAME = wordpress
DB_USER = wpuser
DB_HOST = mariadb:3306
```

Do not print:

```text
DB_PASSWORD
```

The database password is written into `wp-config.php` during configuration creation. Treat this file as sensitive.

---

## 10. Check the environment configuration

Show the non-secret environment variables received by WordPress:

```bash
docker exec wordpress env \
    | grep -E '^(DOMAIN_NAME|MYSQL_HOST|MYSQL_DATABASE|MYSQL_USER|MARIADB_PORT|WP_TITLE|WP_ADMIN_USER|WP_ADMIN_EMAIL|WP_USER|WP_USER_EMAIL)=' \
    | sort
```

Expected important values:

```text
DOMAIN_NAME=tsargsya.42.fr
MYSQL_HOST=mariadb
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MARIADB_PORT=3306
WP_ADMIN_USER=tsargsya
WP_USER=writer
```

The WordPress container receives configuration from:

```text
srcs/.env
srcs/environment/database.env
srcs/environment/wordpress.env
```

Passwords must not appear in this output because they are provided through Docker secrets.

---

## 11. Check Docker secrets

The WordPress container requires:

```text
/run/secrets/db_password
/run/secrets/wp_admin_password
/run/secrets/wp_user_password
```

Check that the files exist and are not empty without printing their contents:

```bash
docker exec wordpress sh -c '
    for file in \
        /run/secrets/db_password \
        /run/secrets/wp_admin_password \
        /run/secrets/wp_user_password
    do
        if [ -s "$file" ]; then
            echo "$file: OK"
        else
            echo "$file: missing or empty"
        fi
    done
'
```

Check the source files on the VM:

```bash
ls -l \
    secrets/db_password.txt \
    secrets/wp_admin_password.txt \
    secrets/wp_user_password.txt
```

Expected permissions:

```text
-rw-------
```

Do not print secrets into logs or commit them to Git.

Important:

> Changing `db_password.txt` does not automatically change the password already stored in MariaDB.

The MariaDB user password and the matching secret must remain synchronized.

---

## 12. Check the Docker network

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

Both services must appear in the network:

```text
mariadb
wordpress
```

After NGINX is implemented, it must appear in the same network as well.

---

## 13. Check Docker DNS

From WordPress, check that the MariaDB service name resolves:

```bash
docker exec wordpress getent hosts mariadb
```

Expected result:

```text
<container-ip> mariadb
```

WordPress must connect to:

```text
mariadb:3306
```

Do not use:

```text
localhost
127.0.0.1
```

Inside the WordPress container, `localhost` refers to the WordPress container itself.

After NGINX is implemented, test WordPress name resolution from NGINX:

```bash
docker exec nginx getent hosts wordpress
```

NGINX should connect to:

```text
wordpress:9000
```

Docker DNS resolves service names to their current container IP addresses.

---

## 14. Test MariaDB from the WordPress container

Run the same type of authenticated query used by the entrypoint:

```bash
docker exec wordpress sh -c '
    MYSQL_PWD="$(tr -d "\r\n" < /run/secrets/db_password)" \
    mariadb \
        --protocol=tcp \
        --host="$MYSQL_HOST" \
        --port="$MARIADB_PORT" \
        --user="$MYSQL_USER" \
        --database="$MYSQL_DATABASE" \
        --execute="SELECT 1"
'
```

Expected result:

```text
1
```

This confirms that:

- Docker DNS resolves `mariadb`;
- MariaDB accepts TCP connections;
- port `3306` is reachable;
- `wpuser` exists;
- the password is correct;
- the `wordpress` database exists;
- the user can execute SQL queries.

Common errors:

```text
Unknown server host
→ Docker DNS or MYSQL_HOST problem

Can't connect to server
→ MariaDB is not ready or the port is incorrect

Access denied
→ username, password, host or privileges are incorrect

Unknown database
→ the wordpress database does not exist
```

---

## 15. Check whether WordPress is installed

Run:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html core is-installed \
    && echo "WordPress is installed"
```

Successful execution confirms that:

- `wp-config.php` is readable;
- MariaDB is reachable;
- WordPress tables exist;
- the site initialization completed.

Important distinction:

```text
WordPress files exist
≠
WordPress is installed in MariaDB
```

`wp core download` creates files.

`wp core install` creates the WordPress database tables and initial site data.

---

## 16. Check the site configuration

Check the site URL:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html option get siteurl
```

Expected result:

```text
https://tsargsya.42.fr
```

Check the home URL:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html option get home
```

Check the site title:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html option get blogname
```

Expected title:

```text
Inception
```

An incorrect URL may cause:

- redirects to the wrong domain;
- broken login redirects;
- incorrect links;
- HTTP instead of HTTPS URLs.

---

## 17. Check WordPress users

List users and roles:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html user list \
        --fields=ID,user_login,user_email,roles
```

Expected users:

```text
tsargsya   administrator
writer     author
```

The project requires:

- one administrator;
- one additional non-administrator user.

The administrator username must not contain:

```text
admin
administrator
```

Examples of invalid usernames:

```text
admin
administrator
myadmin
admin_user
```

Check only administrators:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html user list \
        --role=administrator \
        --fields=ID,user_login,user_email
```

Check the second user:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html user get writer
```

---

## 18. Check the WordPress volume data on the VM

WordPress files are stored in:

```text
/home/tsargsya/data/wordpress
```

Inspect the directory:

```bash
sudo ls -la /home/tsargsya/data/wordpress
```

Expected important files and directories:

```text
wp-admin/
wp-content/
wp-includes/
wp-config.php
wp-load.php
index.php
```

Possible content inside `wp-content`:

```text
themes/
plugins/
uploads/
```

The `uploads` directory may not exist until a file has been uploaded.

Do not manually delete individual WordPress core files while the service is running.

---

## 19. Check the mounted volume

Inspect the container mounts:

```bash
docker inspect wordpress \
    --format '{{json .Mounts}}'
```

The container destination should be:

```text
/var/www/html
```

The host source should ultimately reference:

```text
/home/tsargsya/data/wordpress
```

Inspect the Docker volume object:

```bash
docker volume inspect wordpress_data
```

The WordPress files must be stored in the volume, not only in the temporary writable layer of the container.

---

## 20. Check the resolved Compose configuration

Run:

```bash
docker compose -f srcs/docker-compose.yml config
```

Use this command to verify:

- WordPress build context;
- image and container name;
- environment files;
- Docker secrets;
- `depends_on`;
- volume destination;
- Docker network;
- restart policy;
- absence of a published `9000` port.

Expected WordPress volume destination:

```text
/var/www/html
```

Expected internal network:

```text
inception
```

Expected restart policy:

```text
on-failure
```

---

## 21. Restart WordPress

Normal restart:

```bash
docker compose -f srcs/docker-compose.yml restart wordpress
```

Rebuild and recreate the service:

```bash
docker compose -f srcs/docker-compose.yml up \
    -d \
    --build \
    --force-recreate \
    wordpress
```

Then check:

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs --tail=100 wordpress
```

A normal restart with preserved volumes should not:

- download WordPress again;
- recreate `wp-config.php`;
- reinstall the site;
- recreate existing users.

---

## 22. Understand data persistence

Stop and remove containers:

```bash
docker compose -f srcs/docker-compose.yml down
```

Result:

```text
Container removed
Docker volume preserved
Host WordPress files preserved
MariaDB data preserved
Site preserved
```

Start the project again:

```bash
make
```

The entrypoint should reuse the existing state.

Remove the Docker volume objects:

```bash
docker compose -f srcs/docker-compose.yml down --volumes
```

With the current bind-backed named volumes:

```text
Container removed
Docker volume object removed
Host WordPress directory preserved
WordPress files preserved
```

The host directory is removed by:

```bash
make fclean
```

The current `fclean` target removes:

```text
/home/tsargsya/data
```

This deletes both:

```text
MariaDB data
WordPress files
```

The next `make` performs a complete fresh installation.

---

## 23. Understand partial WordPress data loss

Delete only the WordPress files:

```bash
docker compose -f srcs/docker-compose.yml down

sudo rm -rf /home/tsargsya/data/wordpress
mkdir -p /home/tsargsya/data/wordpress

docker compose -f srcs/docker-compose.yml up -d
```

If the MariaDB volume is preserved, the next startup will:

```text
download WordPress files again
create wp-config.php again
connect to the old MariaDB database
detect that WordPress is already installed
reuse existing users, publications and settings
```

However, file-based content may be lost:

```text
uploaded images
custom themes
installed plugins
manual file changes
```

This may create an inconsistent site:

```text
Database references still exist
but matching files no longer exist
```

Deleting the WordPress volume alone is not a complete WordPress reset.

---

## 24. Test cold and warm starts

### Cold start

Run:

```bash
make fclean
make
```

Expected WordPress behavior:

```text
download core files
wait for MariaDB
create wp-config.php
install WordPress
create administrator
create second user
start PHP-FPM
```

### Warm start

Run:

```bash
make down
make
```

Expected WordPress behavior:

```text
reuse WordPress files
wait for MariaDB
reuse wp-config.php
detect existing WordPress installation
reuse existing users
start PHP-FPM
```

The warm start must preserve:

- users;
- publications;
- settings;
- themes;
- plugins;
- uploaded files.

---

# Fast Diagnostic Path

For a quick investigation, start with:

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs --tail=100 wordpress

docker exec wordpress sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'

docker exec wordpress php-fpm8.2 -t

docker exec wordpress sh -c '
    ls -ld \
        /var/www/html \
        /var/www/html/wp-load.php \
        /var/www/html/wp-config.php
'

docker exec wordpress getent hosts mariadb

sudo ls -la /home/tsargsya/data/wordpress
```

Then test MariaDB:

```bash
docker exec wordpress sh -c '
    MYSQL_PWD="$(tr -d "\r\n" < /run/secrets/db_password)" \
    mariadb \
        --protocol=tcp \
        --host="$MYSQL_HOST" \
        --port="$MARIADB_PORT" \
        --user="$MYSQL_USER" \
        --database="$MYSQL_DATABASE" \
        --execute="SELECT 1"
'
```

Then test WordPress:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html core is-installed

docker exec -u www-data wordpress \
    wp --path=/var/www/html option get siteurl

docker exec -u www-data wordpress \
    wp --path=/var/www/html user list \
        --fields=ID,user_login,user_email,roles
```

---

# Troubleshooting Logic to Remember

```text
1. Is the WordPress container running?
2. What is the last error in the logs?
3. Is php-fpm8.2 -F the main process?
4. Is the PHP-FPM configuration valid?
5. Does PHP-FPM listen internally on port 9000?
6. Do the WordPress core files exist?
7. Does wp-config.php exist?
8. Are the files owned by www-data?
9. Are the required environment variables present?
10. Are all three secret files present and non-empty?
11. Does the hostname mariadb resolve?
12. Can WordPress authenticate to MariaDB and execute SELECT 1?
13. Does wp core is-installed succeed?
14. Are the site URL and title correct?
15. Do the administrator and second user exist with correct roles?
16. Is /var/www/html mounted to the WordPress volume?
17. Are the files present in /home/tsargsya/data/wordpress?
18. Does a warm restart preserve the complete site?
```
## What MariaDB is

MariaDB is a relational database management system.

It stores structured data in databases and allows applications to create,
read, update, and delete that data using SQL.

## Role in this project

MariaDB stores all persistent WordPress database data, including:

- users;
- posts and pages;
- comments;
- site settings;
- plugin and theme configuration.

WordPress connects to MariaDB through the internal Docker network using:

```text
mariadb:3306
```

Adminer also connects to MariaDB using the same internal service name:

```text
mariadb
```

MariaDB is not published directly on the VM.

Its database files are persisted through the `mariadb_data` volume.

## Important project properties

```text
Service name: mariadb
Internal port: 3306
Published port: none
Persistent volume: mariadb_data
Data path in container: /var/lib/mysql
Data path on VM: /home/tsargsya/data/mariadb
```

# MariaDB Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container → Logs → Process → MariaDB → Network → Authentication → Database → Volume
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
mariadb   Up
```

Useful states:

- `Up` — the container's main process is running.
- `Restarting` — the main process repeatedly exits with an error.
- `Exited (1)` — the container stopped with an error.
- `Exited (0)` — the container stopped normally.

Important:

> `Up` does not necessarily mean that MariaDB is ready to accept SQL connections.

---

## 2. Read the MariaDB logs

```bash
docker logs mariadb
```

Show only the last 100 lines:

```bash
docker logs --tail=100 mariadb
```

Follow logs in real time:

```bash
docker logs -f mariadb
```

Look for messages such as:

```text
ready for connections
```

Common error categories:

- permission denied;
- invalid MariaDB configuration;
- missing secret;
- authentication failure;
- damaged data directory;
- MariaDB started as the wrong Linux user;
- initialization SQL failure.

Stop live log output with:

```text
Ctrl + C
```

---

## 3. Check the main process

```bash
docker exec mariadb ps -o pid,user,comm,args
```

Expected main process:

```text
PID 1
User: mysql
Command: mariadbd --user=mysql
```

The permanent MariaDB process should be PID 1 because the entrypoint finishes with:

```sh
exec "$@"
```

---

## 4. Check whether MariaDB responds to SQL

Open the MariaDB client as root:

```bash
docker exec -it mariadb mariadb \
    --protocol=socket \
    --socket=/run/mysqld/mysqld.sock \
    --user=root \
    --password
```

Enter the current MariaDB root password when prompted.

Then run:

```sql
SELECT 1;
```

Expected result:

```text
1
```

This confirms that:

- the server is running;
- the socket is available;
- authentication works;
- MariaDB can execute SQL queries.

Exit the MariaDB client:

```sql
EXIT;
```

---

## 5. Check the MariaDB address and port

Inside the MariaDB client:

```sql
SHOW VARIABLES LIKE 'bind_address';
SHOW VARIABLES LIKE 'port';
```

Expected values:

```text
bind_address = 0.0.0.0
port         = 3306
```

Meaning:

- `0.0.0.0` — MariaDB listens on the container's network interfaces;
- `3306` — MariaDB's internal service port.

Optional operating-system check:

```bash
docker exec mariadb ss -lnt
```

Expected listening port:

```text
0.0.0.0:3306
```

---

## 6. Check the Docker network

List Docker networks:

```bash
docker network ls
```

With the current Compose project and network names, the generated network is normally:

```text
inception_inception
```

Inspect it:

```bash
docker network inspect inception_inception
```

Both services must appear in the same network:

```text
mariadb
wordpress
```

If the exact network name is uncertain:

```bash
docker network ls --filter name=inception
```

---

## 7. Check Docker DNS from WordPress

Run these checks after the WordPress container has been implemented.

Check that the service name resolves:

```bash
docker exec wordpress getent hosts mariadb
```

Expected result:

```text
<container-ip> mariadb
```

The WordPress database host must be:

```text
mariadb
```

or:

```text
mariadb:3306
```

Do not use:

```text
localhost
127.0.0.1
```

Inside the WordPress container, `localhost` refers to WordPress itself, not to the MariaDB container.

Optional port test:

```bash
docker exec wordpress nc -zv mariadb 3306
```

This command requires `nc` to be installed in the WordPress image.

---

## 8. Test the `wpuser` connection

Test the application account through TCP:

```bash
docker exec -it mariadb mariadb \
    --host=127.0.0.1 \
    --port=3306 \
    --user=wpuser \
    --password \
    wordpress
```

Enter the password from:

```text
secrets/db_password.txt
```

Successful connection confirms:

- the `wpuser` account exists;
- its password is correct;
- the `wordpress` database exists;
- the user can access that database;
- MariaDB accepts TCP connections.

A wrong password normally produces:

```text
Access denied for user 'wpuser'
```

---

## 9. Check that the database exists

Connect as root and run:

```sql
SHOW DATABASES;
```

Or check only the project database:

```sql
SHOW DATABASES LIKE 'wordpress';
```

Expected result:

```text
wordpress
```

---

## 10. Check MariaDB users

Connect as root and run:

```sql
SELECT User, Host
FROM mysql.user;
```

Expected application account:

```text
wpuser | %
```

The `%` host means that `wpuser` may connect from another container, including WordPress.

---

## 11. Check `wpuser` privileges

Connect as root and run:

```sql
SHOW GRANTS FOR 'wpuser'@'%';
```

Expected privilege:

```text
GRANT ALL PRIVILEGES ON `wordpress`.* TO `wpuser`@`%`
```

This account should have access to the WordPress database, not unrestricted administrative access to the entire MariaDB server.

---

## 12. Check secrets

Check that the files exist:

```bash
ls -l \
    secrets/db_root_password.txt \
    secrets/db_password.txt
```

Expected permissions:

```text
-rw-------
```

Check that files are not empty without printing their contents:

```bash
test -s secrets/db_root_password.txt \
    && echo "Root password secret exists and is not empty"

test -s secrets/db_password.txt \
    && echo "WordPress database password secret exists and is not empty"
```

Do not print secrets into logs or commit them to Git.

Important:

> Changing a secret file does not automatically change the password already stored inside MariaDB.

Password changes must be performed with SQL first:

```sql
ALTER USER 'wpuser'@'%'
IDENTIFIED BY 'new-password';
```

Then the matching secret file must be updated.

---

## 13. Check initialization state

Check the MariaDB system tables and project marker:

```bash
docker exec mariadb sh -c '
    ls -ld \
        /var/lib/mysql/mysql \
        /var/lib/mysql/.inception_initialized
'
```

Meaning:

```text
/var/lib/mysql/mysql
```

MariaDB system tables have been initialized.

```text
/var/lib/mysql/.inception_initialized
```

The Inception initialization SQL completed successfully.

Possible states:

```text
System tables missing
→ full MariaDB initialization is required

System tables exist, marker missing
→ project SQL must be executed again

System tables and marker exist
→ initialization should be skipped
```

---

## 14. Check volume data on the VM

The MariaDB data is stored in:

```text
/home/tsargsya/data/mariadb
```

Inspect it:

```bash
sudo ls -la /home/tsargsya/data/mariadb
```

This directory should contain MariaDB data files and directories such as:

```text
mysql/
wordpress/
.inception_initialized
```

Do not manually edit MariaDB database files.

---

## 15. Check the mounted volume

Inspect the container mounts:

```bash
docker inspect mariadb \
    --format '{{json .Mounts}}'
```

The container destination should be:

```text
/var/lib/mysql
```

The host source should ultimately reference:

```text
/home/tsargsya/data/mariadb
```

Inspect the Docker volume object:

```bash
docker volume inspect mariadb_data
```

---

## 16. Check the resolved Compose configuration

```bash
docker compose -f srcs/docker-compose.yml config
```

Use this command to verify:

- environment variables;
- service names;
- secrets;
- volumes;
- networks;
- build context;
- restart policy.

This shows the final configuration after Compose processes the YAML file and `.env` values.

---

## 17. Restart MariaDB

Normal restart:

```bash
docker compose -f srcs/docker-compose.yml restart mariadb
```

Rebuild and recreate the service:

```bash
docker compose -f srcs/docker-compose.yml up -d --build --force-recreate mariadb
```

Then check:

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs --tail=100 mariadb
```

---

## 18. Understand data persistence

Stop and remove containers:

```bash
docker compose -f srcs/docker-compose.yml down
```

Result:

```text
Container removed
Docker volume preserved
Host data preserved
WordPress database preserved
```

Remove the Docker volume object:

```bash
docker compose -f srcs/docker-compose.yml down --volumes
```

Result with the current bind-backed named volume:

```text
Container removed
Docker volume object removed
Host directory preserved
WordPress database files preserved
```

Completely remove MariaDB data:

```bash
docker compose -f srcs/docker-compose.yml down --volumes
sudo rm -rf /home/tsargsya/data/mariadb
mkdir -p /home/tsargsya/data/mariadb
```

Result:

```text
System tables removed
WordPress database removed
Users and privileges removed
Initialization marker removed
Next startup performs a fresh initialization
```

Use the destructive reset only when the database data is no longer needed.

---

# Fast Diagnostic Path

For a quick investigation, start with these commands:

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs --tail=100 mariadb
docker exec mariadb ps -o pid,user,comm,args
docker network ls --filter name=inception
sudo ls -la /home/tsargsya/data/mariadb
```

Then test SQL:

```bash
docker exec -it mariadb mariadb \
    --protocol=socket \
    --socket=/run/mysqld/mysqld.sock \
    --user=root \
    --password
```

Inside MariaDB:

```sql
SELECT 1;
SHOW DATABASES LIKE 'wordpress';
SELECT User, Host FROM mysql.user;
SHOW GRANTS FOR 'wpuser'@'%';
```

---

# Troubleshooting Logic to Remember

```text
1. Is the container running?
2. What do the logs say?
3. Is mariadbd the main process?
4. Does MariaDB answer SELECT 1?
5. Does it listen on port 3306?
6. Are MariaDB and WordPress in the same Docker network?
7. Does the hostname mariadb resolve from WordPress?
8. Are the username and password correct?
9. Does the wordpress database exist?
10. Does wpuser have privileges on wordpress.*?
11. Are the volume data and initialization marker present?
```
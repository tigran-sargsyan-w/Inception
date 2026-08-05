## What Redis is

Redis is an in-memory key-value data store.

It keeps data in RAM and is commonly used for:

- application caching;
- sessions;
- counters;
- queues;
- temporary data;
- reducing repeated database work.

Redis does not replace MariaDB in this project.

MariaDB remains the permanent WordPress database. Redis stores temporary
WordPress objects that can be recreated when needed.

## Role in this project

Redis provides an object cache for WordPress.

The request and cache flow is:

```text
Browser
→ HTTPS
→ NGINX :443
→ FastCGI
→ WordPress PHP-FPM :9000
→ Redis Object Cache plugin
→ PhpRedis extension
→ Redis :6379
```

WordPress still uses MariaDB for persistent content:

```text
WordPress
├── MariaDB :3306   permanent database
└── Redis :6379     temporary object cache
```

Redis reduces repeated database queries by keeping frequently used
WordPress objects in memory.

Redis is an internal service:

- it does not publish a host port;
- it is reachable through the Docker network;
- WordPress connects to it with the hostname `redis`;
- it has no persistent volume;
- it does not use Docker secrets;
- its cache may be lost and rebuilt after a restart.

## Important project properties

```text
Service name: redis
Image name: redis:inception
Container name: redis
Internal port: 6379
Published port: none
Configuration file: /etc/redis/redis.conf
Entrypoint: /usr/local/bin/docker-entrypoint.sh
Default command: redis-server /etc/redis/redis.conf
Main process: redis-server
Persistent volume: none
Docker secrets: none
Docker network: inception
WordPress hostname: redis
WordPress port: 6379
WordPress client: PhpRedis
WordPress plugin: Redis Object Cache
Redis persistence: disabled
```

The project uses Redis as a disposable cache, not as permanent storage.

# Redis Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container → Logs → Image Configuration → Entrypoint → Redis Configuration
→ PID 1 → Port → Network → Docker DNS → Redis Ping → WordPress Extension
→ WordPress Configuration → Plugin → Drop-in → Cache Status → Keys
→ Restart Policy → Cold Start
```

You do not need to memorize every command. Remember the troubleshooting
order and use this page as a reference.

---

## 1. Check the container state

Run from the project root:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected result:

```text
redis   Up   6379/tcp
```

Useful states:

- `Up` — the Redis process is running.
- `Restarting` — Redis repeatedly exits with an error.
- `Exited (1)` — the container stopped with an error.
- `Exited (0)` — the container stopped normally.

Important:

> `Up` means that the Redis process is running. It does not guarantee that
> WordPress can resolve the hostname, connect to port `6379`, or use the
> object cache successfully.

Only NGINX publishes a host port:

```text
nginx        published 443
redis       internal 6379 only
wordpress   internal 9000 only
mariadb     internal 3306 only
adminer     internal 9000 only
static_site internal 8080 only
```

Show stopped containers as well:

```bash
docker compose -f srcs/docker-compose.yml ps -a redis
```

---

## 2. Read the Redis logs

```bash
docker logs redis
```

Show only the last 100 lines:

```bash
docker logs --tail=100 redis
```

Follow logs in real time:

```bash
docker logs -f redis
```

A successful startup normally contains:

```text
Configuration loaded
Running mode=standalone, port=6379
Ready to accept connections
```

Common error categories:

- `/etc/redis/redis.conf` is missing or empty;
- invalid Redis configuration;
- port `6379` is already used inside the container;
- Redis cannot bind to the configured address;
- Redis starts in daemon mode and the container exits;
- WordPress cannot resolve the `redis` hostname;
- WordPress cannot connect to port `6379`.

Redis may print:

```text
WARNING Memory overcommit must be enabled
```

For this project, Redis is used as a small non-persistent cache. The warning
does not mean that Redis failed when the log also contains:

```text
Ready to accept connections
```

Stop live log output with:

```text
Ctrl + C
```

---

## 3. Check the image entrypoint and command

Inspect the configuration used by the container:

```bash
docker inspect redis \
    --format \
    'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
```

Expected result:

```text
Entrypoint=["/usr/local/bin/docker-entrypoint.sh"] Cmd=["redis-server","/etc/redis/redis.conf"]
```

The final Docker execution is equivalent to:

```text
/usr/local/bin/docker-entrypoint.sh \
    redis-server /etc/redis/redis.conf
```

The entrypoint validates the configuration file and then executes the
Redis command.

Inspect the Dockerfile:

```bash
cat srcs/requirements/redis/Dockerfile
```

Important instructions:

```dockerfile
COPY conf/redis.conf /etc/redis/redis.conf
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["redis-server", "/etc/redis/redis.conf"]
```

---

## 4. Check the Redis entrypoint

Inspect the entrypoint inside the container:

```bash
docker exec redis cat \
    /usr/local/bin/docker-entrypoint.sh
```

The important logic is:

```sh
REDIS_CONFIG_FILE="/etc/redis/redis.conf"

if [ ! -s "$REDIS_CONFIG_FILE" ]; then
    exit 1
fi

exec "$@"
```

The entrypoint checks that the configuration file:

- exists;
- is a regular readable path for the container;
- is not empty.

The final line:

```sh
exec "$@"
```

replaces the shell with Redis.

The entrypoint does not remain as an extra process.

---

## 5. Check the Redis configuration file

Inspect the active configuration file:

```bash
docker exec redis cat \
    /etc/redis/redis.conf
```

Expected project configuration:

```conf
bind 0.0.0.0
protected-mode no

port 6379

daemonize no
supervised no

save ""
appendonly no
```

Meaning:

- `bind 0.0.0.0` — accept connections through the Docker network;
- `protected-mode no` — allow another container to connect without Redis
  authentication;
- `port 6379` — listen on the standard Redis port;
- `daemonize no` — remain in the foreground;
- `supervised no` — do not expect systemd or another service supervisor;
- `save ""` — disable RDB snapshots;
- `appendonly no` — disable AOF persistence.

Important:

> Redis is not protected by a password in this project. It is isolated by
> the Docker bridge network and port `6379` is not published on the VM.

This is suitable for the local Inception stack. It is not a general
production Redis security configuration.

---

## 6. Check the runtime Redis configuration

Check the values reported by the running server:

```bash
docker exec redis redis-cli CONFIG GET bind
docker exec redis redis-cli CONFIG GET protected-mode
docker exec redis redis-cli CONFIG GET port
docker exec redis redis-cli CONFIG GET daemonize
docker exec redis redis-cli CONFIG GET supervised
docker exec redis redis-cli CONFIG GET save
docker exec redis redis-cli CONFIG GET appendonly
```

Expected important values:

```text
bind
0.0.0.0

protected-mode
no

port
6379

daemonize
no

supervised
no

save

appendonly
no
```

An empty value after `save` confirms that periodic RDB snapshots are
disabled.

---

## 7. Check the main process and PID 1

Show the command running as PID 1:

```bash
docker exec redis sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'
```

Expected result:

```text
PID 1: redis-server 0.0.0.0:6379
```

The exact text may include the configuration path or Redis process title.

The important property is:

```text
PID 1 is redis-server
```

Although Docker Compose displays the entrypoint:

```text
"/usr/local/bin/dock…"
```

the entrypoint finishes with `exec`, so Redis becomes the real main
container process.

This allows Docker signals and restart policies to work correctly.

---

## 8. Check the Redis version

```bash
docker exec redis redis-server --version
```

Check the client version:

```bash
docker exec redis redis-cli --version
```

The packages are installed from Debian Bookworm:

```text
redis-server
redis-tools
```

The exact package version depends on the Debian package repository used
during the image build.

---

## 9. Check the internal Redis port

Inspect the port declared by the image:

```bash
docker inspect redis \
    --format '{{json .Config.ExposedPorts}}'
```

Expected result:

```text
{"6379/tcp":{}}
```

Check whether the port is published on the VM:

```bash
docker port redis
```

Expected result:

```text
No output
```

This is intentional.

Port `6379` is used only inside the Docker network:

```text
WordPress → redis:6379
```

Important:

> `EXPOSE 6379` documents the internal service port. It does not publish
> the port on the host.

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
redis
wordpress
mariadb
nginx
adminer
static_site
```

Redis needs only this internal connection:

```text
WordPress → Redis
```

NGINX does not connect directly to Redis.

---

## 11. Check Docker DNS

From WordPress, resolve the Redis service name:

```bash
docker exec wordpress getent hosts redis
```

Expected result:

```text
<container-ip> redis
```

The correct hostname is:

```text
redis
```

Do not use:

```text
localhost
127.0.0.1
```

Inside the WordPress container, `localhost` refers to WordPress itself,
not to the Redis container.

If the command returns no address, check:

```text
Redis container state
WordPress container state
Docker network membership
Service name in docker-compose.yml
```

---

## 12. Check Redis from inside its own container

```bash
docker exec redis redis-cli ping
```

Expected result:

```text
PONG
```

This confirms:

- the Redis server is running;
- the client can connect locally;
- port `6379` accepts Redis protocol commands.

It does not confirm Docker DNS or WordPress connectivity.

---

## 13. Check WordPress-to-Redis connectivity

Run the Redis client from the WordPress container:

```bash
docker exec wordpress redis-cli \
    -h redis \
    -p 6379 \
    ping
```

Expected result:

```text
PONG
```

This confirms:

- Docker DNS resolves `redis`;
- WordPress and Redis share a network;
- Redis is reachable on port `6379`;
- no Redis password is required.

If local Redis ping works but this command fails, the problem is normally
the Docker network, DNS, hostname or port.

---

## 14. Check the WordPress Redis environment

Inspect the relevant environment variables:

```bash
docker exec wordpress env \
    | grep '^REDIS_'
```

Expected result:

```text
REDIS_HOST=redis
REDIS_PORT=6379
```

The source file is:

```text
srcs/environment/wordpress.env
```

Expected values:

```env
REDIS_HOST=redis
REDIS_PORT=6379
```

No Redis password is stored in the environment file.

---

## 15. Check the PHP Redis extension

List the extension:

```bash
docker exec wordpress php -m \
    | grep -i '^redis$'
```

Expected result:

```text
redis
```

Show detailed extension information:

```bash
docker exec wordpress php --ri redis
```

The WordPress image installs:

```text
php-redis
```

This provides the native `PhpRedis` client used by the WordPress object
cache plugin.

The package:

```text
redis-tools
```

provides `redis-cli`, which the WordPress entrypoint uses while waiting
for Redis to become ready.

---

## 16. Check the WordPress Redis constants

List Redis-related WordPress constants:

```bash
docker exec -u www-data wordpress \
    wp config list \
    --fields=name,value \
    --path=/var/www/html \
    | grep WP_REDIS
```

Expected important values:

```text
WP_REDIS_HOST    redis
WP_REDIS_PORT    6379
```

The WordPress entrypoint configures them with:

```text
WP_REDIS_HOST=redis
WP_REDIS_PORT=6379
```

The entrypoint also removes an old `WP_REDIS_PASSWORD` constant when it
exists.

Check that no password constant remains:

```bash
docker exec -u www-data wordpress \
    wp config has WP_REDIS_PASSWORD \
    --path=/var/www/html
```

Expected result:

```text
Command exits with a non-zero status and prints no value
```

This is intentional because the current Redis service does not require
authentication.

---

## 17. Check the Redis Object Cache plugin

```bash
docker exec -u www-data wordpress \
    wp plugin status redis-cache \
    --path=/var/www/html
```

Expected important value:

```text
Status: Active
```

The plugin is installed by the WordPress entrypoint when it is missing:

```text
wp plugin install redis-cache --activate
```

On later starts, the existing plugin is activated again when necessary.

The plugin provides the WP-CLI command:

```text
wp redis
```

If WordPress reports:

```text
'redis' is not a registered wp command
```

check that the plugin:

- exists;
- is active;
- can be loaded by WordPress.

---

## 18. Check the object-cache drop-in

Inspect the WordPress cache drop-in:

```bash
docker exec wordpress ls -l \
    /var/www/html/wp-content/object-cache.php
```

The file must exist after:

```text
wp redis enable
```

The drop-in is loaded by WordPress before normal plugins and redirects
WordPress object-cache operations to Redis.

Check it through the plugin:

```bash
docker exec -u www-data wordpress \
    wp redis status \
    --path=/var/www/html
```

Expected value:

```text
Drop-in: Valid
```

If the drop-in is missing or invalid, run:

```bash
docker exec -u www-data wordpress \
    wp redis enable \
    --path=/var/www/html
```

---

## 19. Check the complete Redis Object Cache status

```bash
docker exec -u www-data wordpress \
    wp redis status \
    --path=/var/www/html
```

Expected important values:

```text
Status: Connected
Client: PhpRedis
Drop-in: Valid
Disabled: No
Ping: 1
Errors: []
WP_REDIS_HOST: "redis"
WP_REDIS_PORT: 6379
```

Meaning:

- `Connected` — the plugin reached Redis;
- `PhpRedis` — the native PHP Redis extension is used;
- `Drop-in: Valid` — `object-cache.php` is installed correctly;
- `Disabled: No` — object caching is enabled;
- `Ping: 1` — Redis answered the plugin;
- `Errors: []` — the plugin detected no connection error.

This command is the most useful single Redis integration check.

---

## 20. Check whether Redis contains cache keys

```bash
docker exec redis redis-cli dbsize
```

Expected result:

```text
A number greater than 0 after WordPress has been used
```

Generate WordPress requests:

```bash
curl -k -s https://tsargsya.42.fr >/dev/null
curl -k -s https://tsargsya.42.fr/wp-admin/ >/dev/null
```

Check again:

```bash
docker exec redis redis-cli dbsize
```

List a small sample of keys:

```bash
docker exec redis redis-cli --scan \
    | head
```

The exact key names and count may change.

Important:

> A non-zero `dbsize` confirms that WordPress is writing objects to Redis.
> It does not mean that the cache is permanent.

---

## 21. Test WordPress cache operations directly

Create a temporary cache entry:

```bash
docker exec -u www-data wordpress \
    wp cache set inception_test working \
    --path=/var/www/html
```

Read it:

```bash
docker exec -u www-data wordpress \
    wp cache get inception_test \
    --path=/var/www/html
```

Expected value:

```text
working
```

Delete it:

```bash
docker exec -u www-data wordpress \
    wp cache delete inception_test \
    --path=/var/www/html
```

This confirms that WordPress cache commands can write to and read from
the active Redis object cache.

---

## 22. Check Redis memory usage

Show general server information:

```bash
docker exec redis redis-cli INFO server
```

Show memory information:

```bash
docker exec redis redis-cli INFO memory
```

Useful values include:

```text
used_memory
used_memory_human
used_memory_peak
maxmemory
```

Show keyspace information:

```bash
docker exec redis redis-cli INFO keyspace
```

Expected example:

```text
db0:keys=<number>,expires=<number>,avg_ttl=<number>
```

The exact values depend on current WordPress activity.

---

## 23. Check that Redis is intentionally non-persistent

Inspect the project configuration:

```bash
grep -nE '^(save|appendonly)' \
    srcs/requirements/redis/conf/redis.conf
```

Expected result:

```text
save ""
appendonly no
```

Restart Redis:

```bash
docker compose -f srcs/docker-compose.yml restart redis
```

After the restart:

```bash
docker exec redis redis-cli dbsize
```

The cache may be empty or contain only newly recreated keys.

This is expected.

WordPress and MariaDB contain the permanent data. Redis contains only
rebuildable cache data.

---

## 24. Check the restart policy

Inspect the configured policy:

```bash
docker inspect redis \
    --format \
    'policy={{.HostConfig.RestartPolicy.Name}} restart={{.RestartCount}} status={{.State.Status}}'
```

Expected policy:

```text
policy=on-failure
```

A normal manual restart does not test crash recovery.

To test a real Redis process failure, obtain the host PID:

```bash
REDIS_OLD_PID="$(
    docker inspect -f '{{.State.Pid}}' redis
)"

echo "Old PID: $REDIS_OLD_PID"
```

Terminate the process from the host namespace:

```bash
sudo kill -9 "$REDIS_OLD_PID"
```

Wait:

```bash
sleep 5
```

Check the new PID and restart count:

```bash
REDIS_NEW_PID="$(
    docker inspect -f '{{.State.Pid}}' redis
)"

echo "Old PID: $REDIS_OLD_PID"
echo "New PID: $REDIS_NEW_PID"

docker inspect redis \
    --format \
    'restart={{.RestartCount}} status={{.State.Status}}'
```

Expected properties:

```text
Old PID and new PID are different
restart count increased
status=running
```

Then verify Redis and WordPress:

```bash
docker exec redis redis-cli ping

docker exec -u www-data wordpress \
    wp redis status \
    --path=/var/www/html
```

Expected values:

```text
PONG
Status: Connected
```

---

## 25. Check a full rebuild while preserving data

Run:

```bash
make rebuild
```

This target:

- stops the containers;
- preserves the named volumes;
- rebuilds all images without Docker build cache;
- starts the stack again.

After startup:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Check Redis:

```bash
docker exec redis redis-cli ping
```

Check WordPress integration:

```bash
docker exec -u www-data wordpress \
    wp redis status \
    --path=/var/www/html
```

Expected values:

```text
PONG
Status: Connected
Drop-in: Valid
Errors: []
```

WordPress users and MariaDB data must remain present because their named
volumes were preserved.

Redis cache contents may be recreated.

---

## 26. Check a complete cold start

Warning:

> `make re` deletes the MariaDB and WordPress named volumes and removes
> `/home/tsargsya/data`. Existing project data is destroyed.

Run:

```bash
make re
```

Wait for initialization:

```bash
sleep 15
```

Check the services:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Check Redis:

```bash
docker exec redis redis-cli ping
```

Check WordPress:

```bash
docker exec -u www-data wordpress \
    wp core is-installed \
    --path=/var/www/html
```

Check the plugin:

```bash
docker exec -u www-data wordpress \
    wp plugin status redis-cache \
    --path=/var/www/html
```

Check the cache:

```bash
docker exec -u www-data wordpress \
    wp redis status \
    --path=/var/www/html
```

Generate requests and check keys:

```bash
curl -k -s https://tsargsya.42.fr >/dev/null
docker exec redis redis-cli dbsize
```

A successful cold start confirms that:

- Redis is rebuilt from its Dockerfile;
- the configuration file is copied into the image;
- Redis starts before WordPress finishes initialization;
- WordPress waits for Redis;
- the plugin is installed and activated;
- the object-cache drop-in is enabled;
- WordPress writes cache objects to Redis.

---

## 27. Common Redis and WordPress errors

### `Could not connect to Redis at redis:6379: Connection refused`

Meaning:

```text
Docker DNS resolved Redis,
but Redis is not accepting connections on port 6379.
```

Check:

```text
Redis container state
Redis logs
Redis PID 1
redis.conf port
Docker network
```

### `php_network_getaddresses: getaddrinfo for redis failed`

Meaning:

```text
The WordPress container cannot resolve the Redis service name.
```

Check:

```text
Redis container exists and is running
Both containers use the inception network
The service name is redis
REDIS_HOST is redis
```

### `NOAUTH Authentication required`

Meaning:

```text
The running Redis server requires authentication,
but WordPress is configured without a password.
```

The current project intentionally uses no Redis password.

Check for:

```text
an old Redis image
an old requirepass setting
an old redis.conf
an old WP_REDIS_PASSWORD constant
```

### `Error establishing a Redis connection`

Meaning:

```text
The WordPress object-cache drop-in loaded,
but it could not connect to Redis.
```

Check:

```text
docker exec redis redis-cli ping
docker exec wordpress redis-cli -h redis -p 6379 ping
docker exec -u www-data wordpress wp redis status --path=/var/www/html
```

### `'redis' is not a registered wp command`

Meaning:

```text
The Redis Object Cache plugin is missing, inactive or not loaded.
```

Check:

```bash
docker exec -u www-data wordpress \
    wp plugin status redis-cache \
    --path=/var/www/html
```

### `Drop-in: Invalid` or `Drop-in: Missing`

Meaning:

```text
The wp-content/object-cache.php file is missing or does not match the plugin.
```

Run:

```bash
docker exec -u www-data wordpress \
    wp redis enable \
    --path=/var/www/html
```

### Redis starts but the container exits

Check that the configuration contains:

```conf
daemonize no
```

Redis must remain in the foreground and act as PID 1.

---

## 28. Compact Redis health check

Run from the project root:

```bash
printf '\n=== Redis container ===\n'
docker compose -f srcs/docker-compose.yml ps redis

printf '\n=== Redis PID 1 ===\n'
docker exec redis sh -c '
    tr "\0" " " < /proc/1/cmdline
    echo
'

printf '\n=== Redis ping ===\n'
docker exec redis redis-cli ping

printf '\n=== WordPress to Redis ===\n'
docker exec wordpress redis-cli \
    -h redis \
    -p 6379 \
    ping

printf '\n=== PHP extension ===\n'
docker exec wordpress php -m \
    | grep -i '^redis$'

printf '\n=== Object cache status ===\n'
docker exec -u www-data wordpress \
    wp redis status \
    --path=/var/www/html

printf '\n=== Redis keys ===\n'
docker exec redis redis-cli dbsize

printf '\n=== Published port ===\n'
docker port redis
```

Expected important results:

```text
redis container: Up
PID 1: redis-server
Redis ping: PONG
WordPress to Redis: PONG
PHP extension: redis
Status: Connected
Drop-in: Valid
Errors: []
dbsize: greater than 0 after WordPress requests
docker port redis: no output
```

---

## 29. Final Redis checklist

```text
Custom Debian-based Redis image                  OK
Separate Redis container                        OK
Separate redis.conf                             OK
Entrypoint validates the configuration          OK
Redis server is PID 1                           OK
Foreground execution                            OK
Internal port 6379                              OK
No published Redis host port                    OK
Docker DNS hostname redis                       OK
WordPress waits for Redis                       OK
PhpRedis extension installed                    OK
Redis Object Cache plugin active                OK
object-cache.php drop-in valid                  OK
WordPress connected to Redis                    OK
Redis cache contains WordPress keys             OK
No Redis persistent volume                      OK
Cache can be recreated after restart            OK
Restart policy works after a real crash         OK
make rebuild works                              OK
make re cold start works                        OK
```

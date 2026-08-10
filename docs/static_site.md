## What the static site is

The static site is a simple portfolio website written with:

- HTML;
- CSS;
- JavaScript.

It does not use PHP, a database or a content management system.

The website files are served by Python's built-in HTTP server:

```text
python3 -m http.server
```

## Role in this project

The static site satisfies the Inception bonus requirement to provide a
simple static website other than WordPress.

The request flow is:

```text
Browser
→ HTTPS
→ NGINX :443
→ HTTP reverse proxy
→ static_site :8080
→ Python HTTP server
→ HTML, CSS and JavaScript files
```

The static site does not handle TLS directly.

NGINX terminates the HTTPS connection and forwards the request to the
internal Python HTTP server through the Docker network.

The website is available at:

```text
https://portfolio.tsargsya.42.fr
```

The static site is stateless:

- it has no persistent volume;
- it does not connect to MariaDB;
- it does not use Docker secrets;
- it does not publish a host port;
- its files are included in the Docker image.

## Important project properties

```text
Service name: static_site
Image name: static_site:inception
Container name: static_site
Internal port: 8080
Published port: none
Protocol used by NGINX: HTTP
Website root: /var/www/static
Configuration file: /etc/static-site/server.conf
Entrypoint: /usr/local/bin/docker-entrypoint.sh
Default command: serve
Main process: python3 -m http.server
Persistent volume: none
Docker secrets: none
Domain: portfolio.tsargsya.42.fr
```

# Static Site Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container → Logs → Image Configuration → Entrypoint → Server Configuration
→ Static Files → Process → Port → Network → NGINX → Domain → TLS
→ HTTP Response
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
static_site   Up   8080/tcp
```

Useful states:

- `Up` — the container's main process is running.
- `Restarting` — the entrypoint or Python server repeatedly exits.
- `Exited (1)` — the container stopped with an error.
- `Exited (0)` — the container stopped normally.

Important:

> `Up` means that the Python process is running. It does not guarantee
> that NGINX can reach the service, that the domain resolves, or that
> the expected website files are being served.

Only NGINX should publish a port on the VM:

```text
nginx        published 443
static_site  internal 8080 only
adminer      internal 9000 only
wordpress    internal 9000 only
mariadb      internal 3306 only
```

Show stopped containers as well:

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

---

## 2. Read the static site logs

```bash
docker logs static_site
```

Show only the last 100 lines:

```bash
docker logs --tail=100 static_site
```

Follow logs in real time:

```bash
docker logs -f static_site
```

A successful HTTP request normally produces a line similar to:

```text
172.x.x.x - - [...] "GET / HTTP/1.0" 200 -
```

Common error categories:

- the configuration file is missing;
- a required configuration variable is empty;
- the configured port is invalid;
- the website directory does not exist;
- `index.html` is missing or empty;
- Python cannot start the HTTP server;
- port `8080` is already used inside the container;
- NGINX cannot resolve the `static_site` service;
- NGINX cannot connect to port `8080`.

Stop live log output with:

```text
Ctrl + C
```

---

## 3. Check the image entrypoint and command

Inspect the configuration used by the container:

```bash
docker inspect static_site \
    --format \
    'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
```

Expected result:

```text
Entrypoint=["/usr/local/bin/docker-entrypoint.sh"] Cmd=["serve"]
```

The final Docker execution is initially equivalent to:

```text
/usr/local/bin/docker-entrypoint.sh serve
```

The value:

```text
serve
```

is not a Linux executable.

It is a special command understood by the project entrypoint.

The entrypoint transforms it into:

```text
python3 -m http.server 8080 \
    --bind 0.0.0.0 \
    --directory /var/www/static
```

Inspect the Dockerfile:

```bash
cat srcs/requirements/static_site/Dockerfile
```

Expected important instructions:

```dockerfile
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["serve"]
```

---

## 4. Check the entrypoint

Inspect the entrypoint inside the running container:

```bash
docker exec static_site cat \
    /usr/local/bin/docker-entrypoint.sh
```

The entrypoint performs the following steps:

```text
1. Check that server.conf is readable.
2. Load server.conf.
3. Check all required variables.
4. Validate the configured port.
5. Check the website directory.
6. Check that index.html exists and is not empty.
7. Start the Python HTTP server.
```

The configuration is loaded with:

```sh
. "$CONFIG_FILE"
```

The special `serve` command is handled with:

```sh
if [ "${1:-}" = "serve" ]; then
    run_server
fi
```

The server is started through:

```sh
exec python3 \
    -m http.server \
    "$STATIC_SITE_PORT" \
    --bind "$STATIC_SITE_HOST" \
    --directory "$STATIC_SITE_ROOT"
```

The use of `exec` replaces the shell process with Python.

Validate the shell syntax from the project root:

```bash
sh -n \
    srcs/requirements/static_site/tools/docker-entrypoint.sh
```

Expected result:

```text
No output
```

No output means that the shell syntax is valid.

---

## 5. Check the static server configuration

Inspect the source configuration:

```bash
cat \
    srcs/requirements/static_site/conf/server.conf
```

Expected values:

```sh
STATIC_SITE_HOST=0.0.0.0
STATIC_SITE_PORT=8080
STATIC_SITE_ROOT=/var/www/static
```

Inspect the configuration copied into the container:

```bash
docker exec static_site cat \
    /etc/static-site/server.conf
```

Expected values must be identical:

```sh
STATIC_SITE_HOST=0.0.0.0
STATIC_SITE_PORT=8080
STATIC_SITE_ROOT=/var/www/static
```

Meaning:

```text
STATIC_SITE_HOST
→ listen on every network interface inside the container

STATIC_SITE_PORT
→ accept HTTP connections on internal port 8080

STATIC_SITE_ROOT
→ serve files from /var/www/static
```

Important:

> `server.conf` is a project configuration file. It is not a native
> Python `http.server` configuration format.

Python's built-in HTTP server receives its settings through command-line
arguments.

The entrypoint reads `server.conf` and builds those arguments.

Because the configuration is sourced as shell code, its syntax must be
simple variable assignments:

```sh
NAME=value
```

The file is trusted because it is stored in the repository and copied
into the image during the build.

---

## 6. Check the configuration values used by PID 1

Show the actual command line:

```bash
docker exec static_site sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'
```

Expected result:

```text
PID 1: python3 -m http.server 8080 --bind 0.0.0.0 --directory /var/www/static
```

The values should correspond to:

```text
STATIC_SITE_PORT=8080
STATIC_SITE_HOST=0.0.0.0
STATIC_SITE_ROOT=/var/www/static
```

This confirms that the entrypoint loaded the configuration and built the
correct Python command.

---

## 7. Check the main process

Inspect the complete process table:

```bash
docker exec static_site \
    ps -o pid,ppid,user,comm,args
```

If `ps` is not available in the image, use:

```bash
docker top static_site
```

Expected main process:

```text
PID: 1
Command: python3
Arguments: python3 -m http.server 8080 ...
```

The entrypoint itself must not remain as PID 1.

Expected process flow:

```text
docker-entrypoint.sh
→ validates configuration
→ validates website files
→ exec python3 -m http.server
→ Python becomes PID 1
```

Important:

> The container does not use `tail -f`, `sleep infinity`,
> `while true` or another artificial keep-alive command.

The actual web server keeps the container running.

---

## 8. Check the Python version

Show the installed Python version:

```bash
docker exec static_site python3 --version
```

Expected result on the current Debian base:

```text
Python 3.x.x
```

Check that the `http.server` module is available:

```bash
docker exec static_site python3 -c '
import http.server
print("Python http.server: OK")
'
```

Expected result:

```text
Python http.server: OK
```

---

## 9. Check the website directory

List the files:

```bash
docker exec static_site ls -la \
    /var/www/static
```

Expected important files:

```text
index.html
style.css
script.js
```

Check that `index.html` exists and is not empty:

```bash
docker exec static_site sh -c '
    test -s /var/www/static/index.html \
        && echo "index.html: OK"
'
```

Expected result:

```text
index.html: OK
```

Check all website files:

```bash
docker exec static_site sh -c '
    for file in index.html style.css script.js
    do
        if [ ! -s "/var/www/static/$file" ]; then
            echo "$file: missing or empty" >&2
            exit 1
        fi

        echo "$file: OK"
    done
'
```

Expected result:

```text
index.html: OK
style.css: OK
script.js: OK
```

The files are copied into the image during the build:

```dockerfile
COPY website/ /var/www/static/
```

They are not downloaded or generated when the container starts.

---

## 10. Check the internal HTTP server

Test the Python server from inside its own container:

```bash
docker exec static_site python3 -c '
import urllib.request

response = urllib.request.urlopen(
    "http://127.0.0.1:8080/",
    timeout=3
)

print("Status:", response.status)
print("Content-Type:", response.headers.get("Content-Type"))
'
```

Expected result:

```text
Status: 200
Content-Type: text/html
```

This test bypasses NGINX.

It confirms that:

- Python is listening;
- port `8080` is reachable inside the container;
- `index.html` is being served.

It does not confirm:

- Docker DNS;
- NGINX proxying;
- local domain resolution;
- TLS.

---

## 11. Check the internal port

Inspect the port declared by the image:

```bash
docker inspect static_site \
    --format '{{json .Config.ExposedPorts}}'
```

Expected result:

```text
{"8080/tcp":{}}
```

Check whether the port is published on the VM:

```bash
docker port static_site
```

Expected result:

```text
No output
```

This is intentional.

Port `8080` is used only inside the Docker network:

```text
NGINX → HTTP → static_site:8080
```

Important:

> `EXPOSE 8080` documents the internal service port. It does not publish
> the port on the host.

A published port would require a Compose mapping such as:

```yaml
ports:
  - "8080:8080"
```

The static site service does not contain such a mapping.

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

Inspect the network:

```bash
docker network inspect inception_inception
```

Expected services include:

```text
nginx
static_site
adminer
wordpress
mariadb
```

The required static site connection is:

```text
NGINX → static_site
```

Both containers must be connected to the same Docker network.

No host port is required for this connection.

---

## 13. Check Docker DNS

From NGINX, check that the service name resolves:

```bash
docker exec nginx getent hosts static_site
```

Expected result:

```text
<container-ip> static_site
```

The NGINX upstream uses the Compose service name:

```text
static_site
```

Do not use a container IP address in the NGINX configuration.

Container IP addresses can change when containers are recreated.

Do not use:

```text
localhost
127.0.0.1
```

Inside the NGINX container, `localhost` refers to NGINX itself, not to
the static site container.

---

## 14. Validate the NGINX configuration

Run:

```bash
docker exec nginx nginx -t
```

Expected result:

```text
syntax is ok
test is successful
```

Print the active configuration:

```bash
docker exec nginx cat \
    /etc/nginx/conf.d/default.conf
```

The static site server block must contain:

```nginx
server_name portfolio.tsargsya.42.fr;

location / {
    proxy_pass http://static_site:8080;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For
        $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
}
```

Important:

> The static site speaks HTTP, so NGINX uses `proxy_pass`.

WordPress and Adminer use PHP-FPM and therefore require:

```text
fastcgi_pass
```

The static site does not use PHP-FPM, so `fastcgi_pass` would be
incorrect.

---

## 15. Check the generated NGINX domain

The NGINX source template contains:

```nginx
server_name ${STATIC_SITE_DOMAIN};
```

The NGINX entrypoint replaces the variable with:

```text
portfolio.tsargsya.42.fr
```

Check the active generated server block:

```bash
docker exec nginx grep -A25 \
    'server_name portfolio.tsargsya.42.fr' \
    /etc/nginx/conf.d/default.conf
```

Expected upstream:

```nginx
proxy_pass http://static_site:8080;
```

If the active configuration still contains:

```text
${STATIC_SITE_DOMAIN}
```

check:

- `srcs/.env`;
- the NGINX `env_file`;
- the NGINX entrypoint `envsubst` variable list;
- whether the NGINX image was rebuilt.

---

## 16. Check NGINX-to-static-site errors

Show NGINX errors:

```bash
docker exec nginx tail -n 100 \
    /var/log/nginx/error.log
```

Common errors:

```text
host not found in upstream "static_site"
```

Meaning:

```text
Docker DNS cannot resolve static_site,
or NGINX and static_site are not in the same network.
```

```text
connect() failed (111: Connection refused) while connecting to upstream
```

Meaning:

```text
NGINX resolved static_site,
but the Python server is not listening on port 8080.
```

```text
upstream timed out
```

Meaning:

```text
NGINX reached the upstream,
but the upstream did not respond within the configured timeout.
```

```text
502 Bad Gateway
```

Normally indicates an upstream problem.

Check:

```text
static_site container state
Python PID 1
server.conf
port 8080
Docker DNS
NGINX proxy_pass
```

---

## 17. Check local domain resolution

Check the portfolio domain:

```bash
getent hosts portfolio.tsargsya.42.fr
```

Expected result:

```text
127.0.0.1 portfolio.tsargsya.42.fr
```

Inspect the `/etc/hosts` entry:

```bash
grep -n 'portfolio.tsargsya.42.fr' \
    /etc/hosts
```

Expected mapping:

```text
127.0.0.1    portfolio.tsargsya.42.fr    # Inception
```

Check that only one mapping exists:

```bash
grep -c 'portfolio.tsargsya.42.fr' \
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
STATIC_SITE_DOMAIN=portfolio.tsargsya.42.fr
```

inside:

```text
srcs/.env
```

Important:

> TLS certificate configuration does not provide DNS resolution.
> The domain must still resolve through `/etc/hosts` or another DNS
> mechanism.

---

## 18. Check the portfolio TLS hostname

Inspect the certificate Subject Alternative Name:

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

Check the portfolio domain:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkhost portfolio.tsargsya.42.fr
```

Expected result:

```text
Hostname portfolio.tsargsya.42.fr does match certificate
```

Meaning:

```text
DNS:*.tsargsya.42.fr
→ covers portfolio.tsargsya.42.fr
```

The project uses a self-signed certificate.

The hostname can match the certificate while a browser still displays a
certificate-authority warning.

---

## 19. Test the HTTPS response

Check only the response headers:

```bash
curl -k -I \
    https://portfolio.tsargsya.42.fr
```

Expected result:

```text
HTTP/1.1 200 OK
Server: nginx/...
Content-Type: text/html
```

Compact status check:

```bash
curl -k -sS -o /dev/null \
    -w 'Portfolio: HTTP %{http_code}\n' \
    https://portfolio.tsargsya.42.fr
```

Expected result:

```text
Portfolio: HTTP 200
```

Meaning of `-k`:

```text
Ignore public certificate-authority verification
Keep using an encrypted HTTPS connection
```

The option is needed because the project uses a self-signed certificate.

---

## 20. Check the static assets

Check the stylesheet:

```bash
curl -k -I \
    https://portfolio.tsargsya.42.fr/style.css
```

Expected result:

```text
HTTP/1.1 200 OK
Content-Type: text/css
```

Check the JavaScript file:

```bash
curl -k -I \
    https://portfolio.tsargsya.42.fr/script.js
```

Expected result:

```text
HTTP/1.1 200 OK
```

Download the page and check its title:

```bash
curl -k -sS \
    https://portfolio.tsargsya.42.fr \
    | grep -i '<title>'
```

Expected result:

```text
A title from index.html
```

A successful HTML response alone does not prove that CSS and JavaScript
assets are present.

---

## 21. Check the website in a browser

Open:

```text
https://portfolio.tsargsya.42.fr
```

Check that:

- the page loads;
- the CSS styling is applied;
- JavaScript interactions work;
- project cards are visible;
- links work;
- the browser reaches the site through HTTPS.

The browser may display a warning because the project uses a self-signed
certificate.

Accepting the local development certificate warning does not disable
encryption.

---

## 22. Confirm that the static site is stateless

Inspect container mounts:

```bash
docker inspect static_site \
    --format '{{json .Mounts}}'
```

Expected result:

```text
[]
```

The static site does not need:

```text
a persistent volume
a bind mount
a Docker secret
a database connection
a project data directory
```

The website files are part of the Docker image.

Removing and recreating the container does not affect MariaDB or
WordPress data.

To change the website, update files in:

```text
srcs/requirements/static_site/website
```

and rebuild the image.

---

## 23. Check the resolved Compose configuration

Show only the static site service:

```bash
docker compose -f srcs/docker-compose.yml \
    config static_site
```

Or inspect the complete resolved configuration:

```bash
docker compose -f srcs/docker-compose.yml config
```

Expected static site properties:

```text
build context: ./requirements/static_site
image: static_site:inception
container_name: static_site
restart: on-failure
network: inception
no published ports
no volumes
no secrets
no environment file
```

Check that NGINX depends on the service:

```bash
docker compose -f srcs/docker-compose.yml \
    config nginx
```

Expected dependency:

```text
static_site
```

Important:

> `depends_on` controls startup order. It does not prove that the Python
> server is already ready to accept requests.

---

## 24. Restart or rebuild the static site

Restart the existing container:

```bash
docker compose -f srcs/docker-compose.yml \
    restart static_site
```

Rebuild and recreate only the static site:

```bash
docker compose -f srcs/docker-compose.yml \
    up -d --build --force-recreate static_site
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

Do not use `make re` for a routine rebuild because it performs the
destructive `fclean` path first.

After restarting or rebuilding, check:

```bash
docker compose -f srcs/docker-compose.yml ps

curl -k -sS -o /dev/null \
    -w 'Portfolio: HTTP %{http_code}\n' \
    https://portfolio.tsargsya.42.fr
```

---

## 25. Test a missing configuration file

Run a temporary container:

```bash
docker run --rm \
    --entrypoint sh \
    static_site:inception \
    -c '
        rm -f /etc/static-site/server.conf
        exec /usr/local/bin/docker-entrypoint.sh serve
    '
```

Expected error:

```text
Static site entrypoint error: cannot read file: /etc/static-site/server.conf
```

Expected exit status:

```text
non-zero
```

This test modifies only the temporary container.

It does not change the image or the running static site service.

---

## 26. Test an invalid port

Run a temporary container:

```bash
docker run --rm \
    --entrypoint sh \
    static_site:inception \
    -c '
        sed -i \
            "s/STATIC_SITE_PORT=8080/STATIC_SITE_PORT=invalid/" \
            /etc/static-site/server.conf

        exec /usr/local/bin/docker-entrypoint.sh serve
    '
```

Expected error:

```text
Static site entrypoint error: STATIC_SITE_PORT must be a number
```

Test a numeric port outside the valid range:

```bash
docker run --rm \
    --entrypoint sh \
    static_site:inception \
    -c '
        sed -i \
            "s/STATIC_SITE_PORT=8080/STATIC_SITE_PORT=70000/" \
            /etc/static-site/server.conf

        exec /usr/local/bin/docker-entrypoint.sh serve
    '
```

Expected error:

```text
Static site entrypoint error: STATIC_SITE_PORT must be between 1 and 65535
```

---

## 27. Test a missing index file

Run a temporary container:

```bash
docker run --rm \
    --entrypoint sh \
    static_site:inception \
    -c '
        rm -f /var/www/static/index.html
        exec /usr/local/bin/docker-entrypoint.sh serve
    '
```

Expected error:

```text
Static site entrypoint error: index file is missing or empty
```

Expected exit status:

```text
non-zero
```

This confirms that the entrypoint refuses to start an incomplete website.

---

## 28. Test the wrapper behavior

The entrypoint supports replacing the default `serve` command.

Run:

```bash
docker run --rm \
    static_site:inception \
    sh -c 'echo "Custom command: OK"'
```

Expected result:

```text
Custom command: OK
```

Meaning:

```text
The argument is not "serve"
→ entrypoint does not start the Python server
→ entrypoint executes the supplied command through exec "$@"
```

The entrypoint remains a reusable wrapper rather than a script that can
only start one hardcoded command.

---

## 29. Test the restart policy

Check the configured restart policy:

```bash
docker inspect static_site \
    --format '{{.HostConfig.RestartPolicy.Name}}'
```

Expected result:

```text
on-failure
```

Important:

> Do not use `docker stop` or `docker kill` to simulate a process crash.
> Docker treats those as explicit administrative actions and may not
> apply the restart policy.

Allow the container to run normally, then record its restart count and
host PID:

```bash
restart_before="$(
    docker inspect \
        --format '{{.RestartCount}}' \
        static_site
)"

host_pid="$(
    docker inspect \
        --format '{{.State.Pid}}' \
        static_site
)"

echo "Host PID: $host_pid"
echo "Restart count before: $restart_before"
```

Kill the container's main process through the host:

```bash
sudo kill -KILL "$host_pid"
```

Wait briefly and inspect the result:

```bash
sleep 2

docker inspect static_site \
    --format \
    'status={{.State.Status}} restart_count={{.RestartCount}}'
```

Expected result:

```text
status=running
restart_count=<value greater than restart_before>
```

Check the website again:

```bash
curl -k -sS -o /dev/null \
    -w 'Portfolio after crash: HTTP %{http_code}\n' \
    https://portfolio.tsargsya.42.fr
```

Expected result:

```text
Portfolio after crash: HTTP 200
```

This confirms that Docker detected an unexpected process failure and
restarted the container.

---

## 30. Check all public services together

Run:

```bash
curl -k -sS -o /dev/null \
    -w 'WordPress: HTTP %{http_code}\n' \
    https://tsargsya.42.fr

curl -k -sS -o /dev/null \
    -w 'Adminer: HTTP %{http_code}\n' \
    https://adminer.tsargsya.42.fr

curl -k -sS -o /dev/null \
    -w 'Portfolio: HTTP %{http_code}\n' \
    https://portfolio.tsargsya.42.fr
```

Expected result:

```text
WordPress: HTTP 200
Adminer: HTTP 200
Portfolio: HTTP 200
```

This confirms that the static site integration did not break the other
public services.

---

# Fast Diagnostic Path

For a quick investigation, start with:

```bash
docker compose -f srcs/docker-compose.yml ps

docker logs --tail=100 static_site

docker inspect static_site \
    --format \
    'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'

docker exec static_site cat \
    /etc/static-site/server.conf

docker exec static_site sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'

docker exec static_site test -s \
    /var/www/static/index.html

docker port static_site

docker exec nginx getent hosts static_site

docker exec nginx nginx -t

getent hosts portfolio.tsargsya.42.fr

openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkhost portfolio.tsargsya.42.fr

curl -k -I \
    https://portfolio.tsargsya.42.fr
```

---

# Troubleshooting Logic to Remember

```text
1. Is the static_site container running?
2. What do the static site logs say?
3. Does the image use the expected entrypoint and CMD ["serve"]?
4. Is /etc/static-site/server.conf readable?
5. Are STATIC_SITE_HOST, STATIC_SITE_PORT and STATIC_SITE_ROOT set?
6. Is the configured port numeric and between 1 and 65535?
7. Does /var/www/static exist?
8. Does /var/www/static/index.html exist and contain data?
9. Is python3 -m http.server the PID 1 process?
10. Is port 8080 internal and not published?
11. Are NGINX and static_site in the same Docker network?
12. Does NGINX resolve static_site through Docker DNS?
13. Does NGINX use proxy_pass http://static_site:8080?
14. Does portfolio.tsargsya.42.fr resolve to 127.0.0.1?
15. Does the TLS certificate match portfolio.tsargsya.42.fr?
16. Does the homepage return HTTP 200?
17. Do style.css and script.js return HTTP 200?
18. Does the website work correctly in the browser?
```
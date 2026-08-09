## What Dockpeek is

Dockpeek is a lightweight, self-hosted web dashboard for Docker.

It communicates with the Docker Engine and provides a browser interface for:

- discovering Docker containers;
- viewing their current state;
- inspecting container images and published ports;
- viewing container logs;
- following logs in real time;
- checking container and image information.

Dockpeek does not require every container to expose its logs as files.

Instead, it communicates with Docker through the Docker API.

## Role in this project

Dockpeek is the custom bonus service chosen for the Inception project.

Its purpose is to provide a centralized web interface for observing the
containers that make up the Inception infrastructure.

The request flow is:

```text
Browser
→ HTTPS
→ NGINX :443
→ HTTP reverse proxy
→ Dockpeek :8000
→ Docker SDK
→ /var/run/docker.sock
→ Docker Engine
→ Inception containers
```

The Docker monitoring flow is:

```text
Dockpeek
    │
    │ Docker API
    ▼
/var/run/docker.sock
    │
    ├── nginx
    ├── wordpress
    ├── mariadb
    ├── redis
    ├── ftp
    ├── adminer
    ├── static_site
    └── dockpeek
```

Dockpeek therefore discovers the containers automatically.

Individual container log files do not need to be manually mounted into
the Dockpeek container.

The web interface is available at:

```text
https://dockpeek.tsargsya.42.fr
```

Dockpeek itself does not handle TLS.

NGINX terminates HTTPS and forwards requests through the internal Docker
network to:

```text
dockpeek:8000
```

## Why Dockpeek was chosen

Inception contains several independent services running in separate Docker
containers.

Troubleshooting such an infrastructure usually requires commands such as:

```bash
docker compose ps
docker logs <container>
docker inspect <container>
```

Dockpeek provides a single graphical interface where the state and logs of
the containers can be inspected.

This makes it useful for:

- observing the infrastructure;
- checking which containers are running;
- identifying failed services;
- reading container logs;
- following logs during restarts;
- troubleshooting interactions between services.

It was chosen as the custom bonus service because centralized Docker
visibility is directly useful for a multi-container infrastructure project.

## Important project properties

```text
Service name: dockpeek
Image name: dockpeek:inception
Container name: dockpeek

Base image: debian:bookworm
Dockpeek version: v1.7.2

Internal port: 8000
Published port: none
Protocol used by NGINX: HTTP

Domain: dockpeek.tsargsya.42.fr

Entrypoint: /usr/local/bin/docker-entrypoint.sh
Default command: gunicorn -c gunicorn.conf.py run:app
Main process: gunicorn

Environment file:
srcs/environment/dockpeek.env

Username:
USERNAME=dockpeek

Docker secrets:
dockpeek_password
dockpeek_secret_key

Docker socket:
/var/run/docker.sock

Persistent volume: none
Docker network: inception

Authentication: enabled
External access: HTTPS through NGINX only
```

Dockpeek is not directly published on the VM.

The Dockerfile contains:

```dockerfile
EXPOSE 8000
```

but `EXPOSE` only documents the internal container port.

It does not create a host port mapping.

External access remains:

```text
Browser → NGINX :443 → dockpeek:8000
```

# Dockpeek Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container
→ Logs
→ Image Configuration
→ Entrypoint
→ Environment
→ Secrets
→ Gunicorn
→ Internal Port
→ Docker Socket
→ Docker API
→ Network
→ Docker DNS
→ NGINX
→ Domain
→ TLS
→ Authentication
→ Dashboard
→ Live Logs
```

You do not need to memorize every command.

Remember the troubleshooting order and use this page as a reference.

---

## 1. Check the container state

Run from the project root:

```bash
docker compose -f srcs/docker-compose.yml ps dockpeek
```

Expected result:

```text
NAME       IMAGE                SERVICE    STATUS    PORTS
dockpeek   dockpeek:inception   dockpeek   Up        8000/tcp
```

The important properties are:

```text
Status: Up
Internal port: 8000/tcp
Published host port: none
```

Useful states:

- `Up` — the main Dockpeek process is running;
- `Restarting` — the entrypoint or application repeatedly exits;
- `Exited (1)` — the container stopped because of an error;
- `Exited (0)` — the process exited normally.

Important:

> `Up` proves that the container process is alive. It does not prove that
> Dockpeek can communicate with Docker, that NGINX can reach Dockpeek, or
> that authentication works.

---

## 2. Read the Dockpeek logs

Show the container logs:

```bash
docker logs dockpeek
```

Show only the last 100 lines:

```bash
docker logs --tail=100 dockpeek
```

Follow the logs:

```bash
docker logs -f dockpeek
```

Stop following logs with:

```text
Ctrl + C
```

Dockpeek runs behind Gunicorn.

An empty or nearly empty log is not necessarily an error because the
configured Gunicorn log level may not print normal startup information.

If the container is restarting, inspect:

```bash
docker compose -f srcs/docker-compose.yml ps -a dockpeek

docker logs --tail=100 dockpeek
```

Common startup problems include:

```text
missing USERNAME
missing password secret
missing secret-key secret
Docker socket missing
invalid application configuration
Gunicorn startup failure
```

---

## 3. Check the image configuration

Inspect the configured entrypoint and command:

```bash
docker inspect dockpeek \
    --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
```

Expected configuration:

```text
Entrypoint=["/usr/local/bin/docker-entrypoint.sh"]
Cmd=["gunicorn","-c","gunicorn.conf.py","run:app"]
```

The startup sequence is therefore:

```text
Docker
→ docker-entrypoint.sh
→ validate configuration
→ read Docker secrets
→ export PASSWORD and SECRET_KEY
→ exec gunicorn
→ Dockpeek web application
```

---

## 4. Check the PID 1 process

Inspect PID 1:

```bash
docker exec dockpeek sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'
```

The command should contain:

```text
gunicorn
```

The entrypoint finishes with:

```sh
exec "$@"
```

This is important because `exec` replaces the shell process with the
application command.

Therefore the application process becomes PID 1 instead of leaving an
unnecessary shell wrapper running as PID 1.

No infinite-loop command such as:

```text
tail -f
sleep infinity
while true
```

is used to keep the container alive.

---

## 5. Check the Dockpeek version

Inspect the Dockerfile:

```bash
grep -n 'DOCKPEEK_VERSION' \
    srcs/requirements/dockpeek/Dockerfile
```

Expected value:

```text
ARG DOCKPEEK_VERSION=v1.7.2
```

The source is downloaded from the pinned release tag during image build.

Using a pinned version avoids silently changing the installed application
when a newer upstream release appears.

The project does not use a prebuilt Dockpeek Docker image.

Instead:

```text
debian:bookworm
→ install Python
→ download Dockpeek source
→ install Python dependencies
→ run Dockpeek with Gunicorn
```

---

## 6. Check the Python virtual environment

Dockpeek dependencies are installed inside:

```text
/opt/dockpeek-venv
```

Check Python:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/python --version
```

Check Gunicorn:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/gunicorn --version
```

List installed Dockpeek dependencies:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/pip list
```

A virtual environment is used instead of modifying Debian's system Python
environment directly.

---

## 7. Check the normal environment variables

The Dockpeek configuration file is:

```text
srcs/environment/dockpeek.env
```

Its important values are:

```env
USERNAME=dockpeek
TRUST_PROXY_HEADERS=true
TRUSTED_PROXY_COUNT=1
```

Check the username inside the running container:

```bash
docker exec dockpeek sh -c '
    printf "USERNAME=%s\n" "$USERNAME"
'
```

Expected result:

```text
USERNAME=dockpeek
```

Do not print the password or secret key.

`TRUST_PROXY_HEADERS=true` allows Dockpeek to use the forwarded request
information sent by NGINX.

`TRUSTED_PROXY_COUNT=1` reflects the project architecture:

```text
Client → NGINX → Dockpeek
```

There is one reverse proxy between the browser and Dockpeek.

---

## 8. Check Docker secrets

Dockpeek uses two Docker secrets:

```text
dockpeek_password
dockpeek_secret_key
```

Inside the container they are available as:

```text
/run/secrets/dockpeek_password
/run/secrets/dockpeek_secret_key
```

Check that both files exist and are non-empty without printing their
contents:

```bash
docker exec dockpeek sh -c '
    test -s /run/secrets/dockpeek_password \
        && echo "Dockpeek password secret: OK"

    test -s /run/secrets/dockpeek_secret_key \
        && echo "Dockpeek secret key: OK"
'
```

Expected result:

```text
Dockpeek password secret: OK
Dockpeek secret key: OK
```

The entrypoint reads the files:

```sh
PASSWORD="$(tr -d '\r\n' < "$PASSWORD_FILE")"
SECRET_KEY="$(tr -d '\r\n' < "$SECRET_KEY_FILE")"
```

and exports:

```sh
export PASSWORD
export SECRET_KEY
```

Dockpeek therefore receives:

```text
USERNAME
PASSWORD
SECRET_KEY
```

without storing the sensitive values directly in the Dockerfile or the
normal environment file.

Never print or commit the secret values.

---

## 9. Check the entrypoint failure protection

Inspect the entrypoint:

```bash
docker exec dockpeek cat \
    /usr/local/bin/docker-entrypoint.sh
```

Important checks include:

```text
USERNAME must exist
dockpeek_password must exist
dockpeek_secret_key must exist
password must not be empty
secret key must not be empty
```

The entrypoint must fail instead of starting Dockpeek with incomplete
authentication configuration.

---

## 10. Check the internal port

Inspect the image exposed ports:

```bash
docker inspect dockpeek \
    --format '{{json .Config.ExposedPorts}}'
```

Expected result:

```text
{"8000/tcp":{}}
```

Check whether Dockpeek publishes a host port:

```bash
docker port dockpeek
```

Expected result:

```text
No output
```

This is intentional.

Dockpeek must be reached internally through:

```text
dockpeek:8000
```

and externally through:

```text
https://dockpeek.tsargsya.42.fr
```

---

## 11. Check Gunicorn locally inside Dockpeek

Test whether something is listening on port `8000`:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/python \
    -c '
import socket

connection = socket.create_connection(("127.0.0.1", 8000), 3)
connection.close()

print("Dockpeek port 8000: reachable")
'
```

Expected result:

```text
Dockpeek port 8000: reachable
```

This confirms that the application is listening inside the container.

It does not test NGINX or the external domain.

---

## 12. Check the Docker socket

Dockpeek needs access to the Docker Engine.

Check that the socket exists:

```bash
docker exec dockpeek sh -c '
    if [ -S /var/run/docker.sock ]; then
        echo "Docker socket: OK"
    else
        echo "Docker socket: NOT FOUND"
        exit 1
    fi
'
```

Expected result:

```text
Docker socket: OK
```

Inspect the container mount:

```bash
docker inspect dockpeek \
    --format '{{json .Mounts}}'
```

The configuration should include:

```text
Source: /var/run/docker.sock
Destination: /var/run/docker.sock
```

The Compose configuration uses:

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

Important security note:

> Docker socket access is security-sensitive.

The `:ro` bind option prevents filesystem writes to the socket mount itself,
but it must not be interpreted as a complete Docker API permission system.

A process that can communicate with the Docker socket has significant
visibility into the Docker Engine.

For this reason the Dockpeek web interface is not published directly and
is protected by authentication behind NGINX and HTTPS.

---

## 13. Check Docker API access

Use the Docker Python SDK already installed inside Dockpeek:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/python \
    -c '
import docker

client = docker.from_env()

print([container.name for container in client.containers.list()])
'
```

Expected containers include:

```text
dockpeek
ftp
nginx
wordpress
adminer
static_site
mariadb
redis
```

The exact order is not important.

This test confirms:

```text
Dockpeek
→ Docker SDK
→ Docker socket
→ Docker Engine
→ container list
```

If the list cannot be retrieved, check:

```text
Docker socket mount
socket permissions
Docker daemon
Python docker package
```

---

## 14. Check the Docker network

Inspect the Inception network:

```bash
docker network inspect inception_inception
```

Dockpeek and NGINX should both appear in the same network.

Check Docker DNS from NGINX:

```bash
docker exec nginx getent hosts dockpeek
```

Expected result:

```text
<container-ip> dockpeek
```

NGINX uses the Docker service name:

```text
dockpeek
```

not a fixed container IP.

The upstream is therefore:

```text
dockpeek:8000
```

Container IP addresses may change when containers are recreated.

---

## 15. Validate the NGINX configuration

Test the active NGINX configuration:

```bash
docker exec nginx nginx -t
```

Expected result:

```text
syntax is ok
test is successful
```

Inspect the active project configuration:

```bash
docker exec nginx cat \
    /etc/nginx/conf.d/default.conf
```

The Dockpeek server block should contain:

```nginx
server_name dockpeek.tsargsya.42.fr;

location / {
    proxy_pass http://dockpeek:8000;

    proxy_http_version 1.1;
    proxy_buffering off;
    proxy_cache off;

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For
        $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;

    proxy_read_timeout 600s;
}
```

The important flow is:

```text
NGINX
→ Docker DNS resolves dockpeek
→ HTTP
→ dockpeek:8000
```

`proxy_buffering off` is useful for responses that must be delivered
progressively, such as real-time log streams.

---

## 16. Check the Dockpeek domain

Check local resolution:

```bash
getent hosts dockpeek.tsargsya.42.fr
```

Expected result:

```text
127.0.0.1 dockpeek.tsargsya.42.fr
```

Inspect `/etc/hosts`:

```bash
grep -n 'dockpeek.tsargsya.42.fr' \
    /etc/hosts
```

The domain is configured from:

```text
DOCKPEEK_DOMAIN=dockpeek.tsargsya.42.fr
```

inside:

```text
srcs/.env
```

The local mapping is managed by:

```text
tools/configure_domain.sh
```

---

## 17. Check TLS hostname coverage

Inspect the certificate Subject Alternative Names:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -ext subjectAltName
```

Expected names include:

```text
DNS:tsargsya.42.fr
DNS:*.tsargsya.42.fr
```

Check the Dockpeek hostname directly:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkhost dockpeek.tsargsya.42.fr
```

Expected result:

```text
Hostname dockpeek.tsargsya.42.fr does match certificate
```

The wildcard certificate covers the first-level Dockpeek subdomain.

The certificate does not provide DNS resolution by itself.

The hostname still needs the `/etc/hosts` mapping.

---

## 18. Test the HTTPS authentication redirect

Without an authenticated browser session:

```bash
curl -k -I \
    https://dockpeek.tsargsya.42.fr
```

Expected response:

```text
HTTP/1.1 302 FOUND
Location: /login
```

This proves:

```text
domain resolution
→ NGINX :443
→ TLS
→ NGINX virtual host
→ dockpeek:8000
→ Dockpeek application
→ authentication redirect
```

The `302` response is correct because unauthenticated users are redirected
to the login page.

---

## 19. Test browser authentication

Open:

```text
https://dockpeek.tsargsya.42.fr
```

Use:

```text
Username: dockpeek
Password: value stored in secrets/dockpeek_password.txt
```

Do not place the password itself in documentation, screenshots or Git.

After a successful login, the dashboard should display the Inception
containers.

Expected services include:

```text
adminer
dockpeek
ftp
mariadb
nginx
redis
static_site
wordpress
```

The dashboard should report their current state.

Normally all services should show:

```text
running
```

---

## 20. Test live container logs

Open the logs for a container in the Dockpeek web interface.

For example, open the Redis logs.

Then restart Redis:

```bash
docker compose -f srcs/docker-compose.yml \
    restart redis
```

Dockpeek should display the shutdown:

```text
Received SIGTERM scheduling shutdown
User requested shutdown
Redis is now ready to exit
```

followed by the new startup:

```text
Redis is starting
Configuration loaded
Running mode=standalone
Server initialized
Ready to accept connections
```

This confirms that Dockpeek is reading current container logs through the
Docker API and not displaying a static file.

The same technique can be used with other containers.

---

## 21. Check that no individual log volume is required

Inspect Dockpeek mounts:

```bash
docker inspect dockpeek \
    --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```

The important mount is:

```text
/var/run/docker.sock -> /var/run/docker.sock
```

There should not be individual mounts such as:

```text
nginx.log
redis.log
mariadb.log
wordpress.log
```

Dockpeek requests container logs from Docker itself.

The architecture is therefore:

```text
Container stdout/stderr
→ Docker logging system
→ Docker API
→ Dockpeek
→ Web UI
```

---

## 22. Check the resolved Compose configuration

Run:

```bash
docker compose -f srcs/docker-compose.yml config
```

Expected Dockpeek properties include:

```text
build context:
./requirements/dockpeek

image:
dockpeek:inception

container_name:
dockpeek

restart:
on-failure

environment:
USERNAME=dockpeek
TRUST_PROXY_HEADERS=true
TRUSTED_PROXY_COUNT=1

secrets:
dockpeek_password
dockpeek_secret_key

volume:
/var/run/docker.sock

network:
inception

published ports:
none
```

NGINX should depend on Dockpeek:

```text
nginx
└── depends_on
    └── dockpeek
```

Important:

> `depends_on` controls container startup order. It does not guarantee
> application readiness.

---

## 23. Restart Dockpeek

Restart the existing container:

```bash
docker compose -f srcs/docker-compose.yml \
    restart dockpeek
```

Then check:

```bash
docker compose -f srcs/docker-compose.yml \
    ps dockpeek
```

The container should return to:

```text
Up
```

Verify HTTPS again:

```bash
curl -k -I \
    https://dockpeek.tsargsya.42.fr
```

Expected unauthenticated response:

```text
302
Location: /login
```

---

## 24. Rebuild Dockpeek

Rebuild and recreate only Dockpeek:

```bash
docker compose -f srcs/docker-compose.yml \
    up -d --build --force-recreate dockpeek
```

Then verify:

```bash
docker compose -f srcs/docker-compose.yml \
    ps dockpeek
```

and:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/python \
    -c '
import docker

print([container.name for container in docker.from_env().containers.list()])
'
```

This confirms that a recreated Dockpeek container can reconnect to the
Docker Engine.

---

## 25. Test a complete cold start

Warning:

> `make fclean` removes the project containers, images, volumes and the
> persistent project data directory.

Use this test only when destructive cleanup is intended.

Run:

```bash
make fclean
```

Verify that the project containers are gone:

```bash
docker compose -f srcs/docker-compose.yml ps -a
```

Then rebuild the complete infrastructure:

```bash
make
```

After startup:

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

After a short wait, verify that Dockpeek is still running:

```bash
docker compose -f srcs/docker-compose.yml \
    ps dockpeek
```

Verify HTTPS:

```bash
curl -k -I \
    https://dockpeek.tsargsya.42.fr
```

Verify Docker API access:

```bash
docker exec dockpeek \
    /opt/dockpeek-venv/bin/python \
    -c '
import docker

print([container.name for container in docker.from_env().containers.list()])
'
```

Finally log in through the browser and confirm that all project containers
appear in the dashboard.

A successful cold start proves that Dockpeek does not depend on manual
post-start configuration.

---

## 26. Security considerations

Dockpeek requires Docker Engine access in order to discover containers and
retrieve their logs.

The Docker socket is therefore the most sensitive part of this service.

Important properties of the project configuration are:

```text
Dockpeek has no directly published host port.
External access goes through NGINX.
NGINX provides HTTPS.
Dockpeek authentication is enabled.
The password is stored as a Docker secret.
The application secret key is stored as a Docker secret.
```

The Docker socket should always be considered privileged infrastructure
access.

The `:ro` mount flag must not be treated as a complete authorization
boundary for Docker API operations.

For a production environment, a restricted Docker socket proxy could
provide stronger API-level isolation.

For this project, access to the Dockpeek interface is restricted through
authentication and the service is not exposed directly to the host.

---

# Fast Diagnostic Path

For a quick Dockpeek investigation:

```bash
docker compose -f srcs/docker-compose.yml ps dockpeek

docker logs --tail=100 dockpeek

docker exec dockpeek sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'

docker exec dockpeek sh -c '
    printf "USERNAME=%s\n" "$USERNAME"
'

docker exec dockpeek sh -c '
    test -s /run/secrets/dockpeek_password \
        && echo "password secret: OK"

    test -s /run/secrets/dockpeek_secret_key \
        && echo "secret key: OK"
'

docker exec dockpeek sh -c '
    test -S /var/run/docker.sock \
        && echo "Docker socket: OK"
'

docker exec dockpeek \
    /opt/dockpeek-venv/bin/python \
    -c '
import docker
print([container.name for container in docker.from_env().containers.list()])
'

docker exec nginx getent hosts dockpeek

docker exec nginx nginx -t

getent hosts dockpeek.tsargsya.42.fr

openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkhost dockpeek.tsargsya.42.fr

curl -k -I \
    https://dockpeek.tsargsya.42.fr
```

Then open:

```text
https://dockpeek.tsargsya.42.fr
```

and verify:

```text
login
→ dashboard
→ all containers visible
→ logs open
→ live log updates
```

---

# Troubleshooting Logic to Remember

```text
1. Is the Dockpeek container running?
2. What do the Dockpeek logs say?
3. Is Gunicorn running as PID 1?
4. Did the entrypoint receive USERNAME?
5. Are both Dockpeek secret files present?
6. Did the entrypoint export PASSWORD and SECRET_KEY?
7. Is Dockpeek listening on port 8000?
8. Is port 8000 internal and not published?
9. Is /var/run/docker.sock mounted?
10. Can the Docker Python SDK connect through the socket?
11. Can Dockpeek list the Inception containers?
12. Are Dockpeek and NGINX in the same Docker network?
13. Can NGINX resolve the hostname dockpeek?
14. Is the NGINX configuration valid?
15. Does NGINX proxy to dockpeek:8000?
16. Does dockpeek.tsargsya.42.fr resolve to 127.0.0.1?
17. Does the TLS certificate match the Dockpeek hostname?
18. Does an unauthenticated HTTPS request redirect to /login?
19. Can the configured user log in?
20. Does the dashboard show all Inception containers?
21. Can Dockpeek display container logs?
22. Do live logs update after a container restart?
23. Does Dockpeek work again after make fclean followed by make?
```
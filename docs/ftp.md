## What FTP is

FTP (File Transfer Protocol) is a protocol for transferring files between a
client and a server.

Unlike HTTP, FTP uses separate connections for commands and file data.

The control connection normally uses port `21` and carries commands such as:

```text
USER
PASS
PWD
CWD
LIST
STOR
RETR
DELE
```

File listings, uploads and downloads use a separate data connection.

This project uses passive FTP mode. The client opens both the control
connection and the data connection to the server.

FTP in this project is plain FTP, not FTPS. The bonus service is intended for
the local Inception environment; FTP itself does not provide TLS encryption.

## Role in this project

The FTP service provides authenticated read and write access to the same files
used by WordPress.

The main data flow is:

```text
FTP client
→ FTP control connection :21
→ ProFTPD
→ passive data connection :21000-21010
→ wordpress_data
```

The WordPress and FTP containers mount the same named volume:

```text
FTP /var/www/html
        │
        └── wordpress_data
                │
                └── WordPress /var/www/html
```

The named volume is backed by:

```text
/home/tsargsya/data/wordpress
```

A file uploaded through FTP therefore becomes immediately visible inside the
WordPress container.

NGINX also mounts the same WordPress volume read-only, so normal static files
placed in the WordPress tree may also be reachable through HTTPS when the
NGINX configuration allows it.

FTP does not pass through NGINX:

```text
HTTPS client → NGINX :443
FTP client   → ProFTPD :21 + passive ports
```

The FTP service is a bonus service and publishes its own required ports.

## Important project properties

```text
Service name: ftp
Image name: ftp:inception
Container name: ftp
FTP server: ProFTPD
Control port: 21
Passive ports: 21000-21010
Published ports: 21 and 21000-21010
Configuration template: /etc/proftpd/proftpd.conf.template
Generated configuration: /etc/proftpd/proftpd.conf
Entrypoint: /usr/local/bin/docker-entrypoint.sh
Default command: /usr/sbin/proftpd -n -c /etc/proftpd/proftpd.conf
Main process: proftpd
FTP user: ftpuser
FTP UID/GID: 33:33
FTP home: /var/www/html
Docker secret: ftp_password
Secret path in container: /run/secrets/ftp_password
Shared volume: wordpress_data
Volume mount path: /var/www/html
Host data path: /home/tsargsya/data/wordpress
Docker network: inception
```

The project deliberately keeps the FTP user's numeric UID and GID equal to
WordPress `www-data`:

```text
FTP container:       UID 33 → ftpuser
WordPress container: UID 33 → www-data
```

Linux filesystems store numeric UID/GID values, not usernames. This allows
files created through FTP to remain compatible with WordPress permissions.

## Configuration consistency note

The current FTP environment file contains:

```env
FTP_PORT=21
FTP_PASV_ADDRESS=127.0.0.1
FTP_PASV_MIN_PORT=21000
FTP_PASV_MAX_PORT=21010
```

The same control and passive ports are published explicitly in
`docker-compose.yml`:

```yaml
ports:
  - "21:21"
  - "21000-21010:21000-21010"
```

If the FTP port or passive range is changed in `ftp.env`, the Compose port
mappings must be updated to match.

`FTP_PASV_ADDRESS=127.0.0.1` is suitable when the FTP client connects through
the VM's loopback address. If the client connects from another machine, the
passive address must be an address reachable by that client.

# FTP Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container → Logs → Image → Environment → Secret → Entrypoint
→ Generated Configuration → PID 1 → FTP User → Ports → Passive Mode
→ Authentication → LIST → Upload → Download → Shared Volume → Permissions
→ Restart Policy → Persistence → Rebuild → Cold Start
```

You do not need to memorize every command. Remember the troubleshooting
order and use this page as a reference.

---

## 1. Check the container state

Run from the project root:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected FTP result:

```text
ftp   Up   0.0.0.0:21->21/tcp, 0.0.0.0:21000-21010->21000-21010/tcp
```

Useful states:

- `Up` — ProFTPD is running.
- `Restarting` — the entrypoint or ProFTPD repeatedly exits with an error.
- `Exited (1)` — startup failed with an error.
- `Exited (0)` — the process stopped normally.

Important:

> `Up` confirms that the container's main process is running. It does not by
> itself prove authentication, passive transfers or access to the WordPress
> volume.

Show stopped FTP containers as well:

```bash
docker compose -f srcs/docker-compose.yml ps -a ftp
```

---

## 2. Read the FTP logs

```bash
docker logs ftp
```

Show only recent lines:

```bash
docker logs --tail=100 ftp
```

Follow logs in real time:

```bash
docker logs -f ftp
```

A successful startup normally contains text similar to:

```text
ProFTPD ... standalone mode STARTUP
```

Successful sessions may contain:

```text
FTP session opened
USER ftpuser: Login successful
FTP session closed
```

Common error categories:

- missing FTP environment variables;
- missing or empty FTP password secret;
- invalid generated ProFTPD configuration;
- control port already in use;
- passive ports are not published correctly;
- wrong passive address;
- authentication failure;
- permission denied on the WordPress volume.

Stop live log output with:

```text
Ctrl + C
```

---

## 3. Check the image entrypoint and command

Inspect the Docker configuration:

```bash
docker inspect ftp \
    --format \
    'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}'
```

Expected result:

```text
Entrypoint=["/usr/local/bin/docker-entrypoint.sh"] Cmd=["/usr/sbin/proftpd","-n","-c","/etc/proftpd/proftpd.conf"]
```

The final Docker execution is equivalent to:

```text
/usr/local/bin/docker-entrypoint.sh \
    /usr/sbin/proftpd -n -c /etc/proftpd/proftpd.conf
```

Inspect the Dockerfile:

```bash
cat srcs/requirements/ftp/Dockerfile
```

Important installed packages:

```text
gettext-base   provides envsubst
passwd         provides account/password management tools
proftpd-core   provides the FTP server
```

The Dockerfile also declares:

```dockerfile
EXPOSE 21 21000-21010
```

Remember:

> `EXPOSE` documents container ports. The `ports:` section in Compose is what
> actually publishes ports on the VM.

---

## 4. Check the FTP environment

Inspect the source file:

```bash
cat srcs/environment/ftp.env
```

Expected values:

```env
FTP_USER=ftpuser

FTP_PORT=21

FTP_PASV_ADDRESS=127.0.0.1
FTP_PASV_MIN_PORT=21000
FTP_PASV_MAX_PORT=21010
```

Inspect the running container environment:

```bash
docker exec ftp env | grep '^FTP_'
```

Expected values must match the source environment file.

The password must not be stored here.

---

## 5. Check the FTP secret

The secret source is:

```text
secrets/ftp_password.txt
```

It is generated by:

```bash
python3 tools/generate_secrets.py
```

Check that the host file exists without printing its contents:

```bash
test -s secrets/ftp_password.txt \
    && echo 'FTP secret exists: OK'
```

Check host permissions:

```bash
stat -c '%a %n' secrets/ftp_password.txt
```

Expected permissions:

```text
600 secrets/ftp_password.txt
```

Check the mounted secret inside the container without displaying it:

```bash
docker exec ftp sh -c '
    test -s /run/secrets/ftp_password \
        && echo "FTP secret mounted: OK"
'
```

The entrypoint reads the secret and passes it to `chpasswd`.

The password is not stored in:

```text
Dockerfile
ftp.env
proftpd.conf
Git repository
```

---

## 6. Check the FTP entrypoint

Inspect the running entrypoint script:

```bash
docker exec ftp cat \
    /usr/local/bin/docker-entrypoint.sh
```

The entrypoint validates:

```text
FTP_USER
FTP_PORT
FTP_PASV_ADDRESS
FTP_PASV_MIN_PORT
FTP_PASV_MAX_PORT
/run/secrets/ftp_password
```

If an expected value is missing, the container exits instead of starting a
partially configured FTP server.

The entrypoint then:

```text
1. renames the Debian www-data group to ftpuser;
2. renames the Debian www-data user to ftpuser;
3. keeps UID/GID 33:33;
4. sets /var/www/html as the FTP home;
5. sets the password with chpasswd;
6. generates proftpd.conf with envsubst;
7. executes ProFTPD with exec "$@".
```

The final line:

```sh
exec "$@"
```

replaces the shell process with ProFTPD so ProFTPD becomes the real container
main process.

---

## 7. Check environment substitution

The image contains a template:

```text
/etc/proftpd/proftpd.conf.template
```

The entrypoint creates:

```text
/etc/proftpd/proftpd.conf
```

using:

```sh
envsubst \
    '${FTP_PORT} ${FTP_PASV_ADDRESS} ${FTP_PASV_MIN_PORT} ${FTP_PASV_MAX_PORT}' \
    < "$PROFTPD_TEMPLATE" \
    > "$PROFTPD_CONFIG"
```

Inspect the active configuration:

```bash
docker exec ftp cat /etc/proftpd/proftpd.conf
```

Check important generated values:

```bash
docker exec ftp grep -E \
    '^(Port|DefaultRoot|PassivePorts|MasqueradeAddress)' \
    /etc/proftpd/proftpd.conf
```

Expected result:

```text
Port 21
DefaultRoot ~
PassivePorts 21000 21010
MasqueradeAddress 127.0.0.1
```

Check that no `${FTP_...}` placeholders remain:

```bash
docker exec ftp sh -c '
    if grep -Fq "\${FTP_" /etc/proftpd/proftpd.conf; then
        echo "ERROR: unresolved FTP placeholder"
        exit 1
    fi
    echo "FTP placeholders: OK"
'
```

Expected result:

```text
FTP placeholders: OK
```

---

## 8. Validate the ProFTPD configuration

Run ProFTPD's syntax check:

```bash
docker exec ftp \
    proftpd -t -c /etc/proftpd/proftpd.conf
```

The command must exit successfully.

Important active directives include:

```conf
ServerType standalone
Port 21
User nobody
Group nogroup
RequireValidShell off
UseFtpUsers off
AuthOrder mod_auth_unix.c
DefaultRoot ~
AllowOverwrite on
Umask 022 022
PassivePorts 21000 21010
MasqueradeAddress 127.0.0.1
```

Meaning:

- `standalone` — ProFTPD runs as its own server process;
- `User nobody` / `Group nogroup` — the main daemon drops privileges;
- `AuthOrder mod_auth_unix.c` — FTP users authenticate against Unix accounts;
- `DefaultRoot ~` — authenticated users are jailed to their home directory;
- `AllowOverwrite on` — existing files may be replaced;
- `Umask 022 022` — normal uploaded files become `644` and directories `755`;
- `PassivePorts` — restrict passive data connections to the published range;
- `MasqueradeAddress` — address advertised to passive clients.

---

## 9. Check the main process and PID 1

The FTP image intentionally does not install `procps` just for debugging.
Use Docker to inspect the process table:

```bash
docker top ftp -eo pid,ppid,user,comm,args
```

Expected main process:

```text
nobody   proftpd   proftpd: (accepting connections)
```

ProFTPD may rewrite its displayed process title after startup.

Check PID 1 from inside the container:

```bash
docker exec ftp sh -c '
    grep -E "^(Name|Pid|PPid):" /proc/1/status
'
```

Expected important values:

```text
Name: proftpd
Pid: 1
PPid: 0
```

The `-n` option keeps ProFTPD in the foreground and `exec "$@"` makes it the
container's PID 1.

---

## 10. Check the FTP user and numeric ownership

Check the account:

```bash
docker exec ftp id ftpuser
```

Expected result:

```text
uid=33(ftpuser) gid=33(ftpuser) groups=33(ftpuser)
```

Inspect the passwd entry:

```bash
docker exec ftp getent passwd ftpuser
```

Expected important fields:

```text
UID: 33
GID: 33
home: /var/www/html
shell: /bin/sh
```

The original Debian account is `www-data` with numeric UID/GID `33:33`.
The entrypoint renames that account instead of creating a new unrelated UID.

This matters because the same files appear as:

```text
FTP container:       ftpuser:ftpuser
WordPress container: www-data:www-data
```

while the filesystem stores the same numeric owner:

```text
33:33
```

Use `ls -ln` when verifying cross-container ownership.

---

## 11. Check the FTP root and chroot behavior

The FTP user's home is:

```text
/var/www/html
```

and ProFTPD contains:

```conf
DefaultRoot ~
```

Therefore the FTP client sees `/var/www/html` as `/`.

A normal directory listing should contain WordPress files such as:

```text
wp-admin
wp-content
wp-includes
wp-config.php
index.php
```

The FTP user should not be able to browse outside the configured FTP root.

---

## 12. Check published FTP ports

Show published mappings:

```bash
docker port ftp
```

Expected mappings include:

```text
21/tcp -> 0.0.0.0:21
21000/tcp -> 0.0.0.0:21000
...
21010/tcp -> 0.0.0.0:21010
```

Inspect the ports declared by the image:

```bash
docker inspect ftp \
    --format '{{json .Config.ExposedPorts}}'
```

The image should expose:

```text
21/tcp
21000/tcp ... 21010/tcp
```

FTP differs from most services in this project because its bonus protocol
requires additional published ports.

---

## 13. Understand and check passive mode

FTP uses two connection types:

```text
Control connection:
client → server:21

Passive data connection:
client → server:21000-21010
```

The control connection carries commands. Directory listings and file transfers
use a data connection.

Passive mode is useful with Docker because the client initiates both
connections.

If login succeeds but LIST, upload or download hangs, check:

```text
PassivePorts in proftpd.conf
MasqueradeAddress
Compose published passive range
firewall rules
address used by the FTP client
```

---

## 14. Check the shared WordPress volume

Inspect FTP mounts:

```bash
docker inspect ftp \
    --format '{{range .Mounts}}{{println .Type .Name .Source "->" .Destination}}{{end}}'
```

The important mount is:

```text
wordpress_data -> /var/www/html
```

Inspect WordPress mounts:

```bash
docker inspect wordpress \
    --format '{{range .Mounts}}{{println .Type .Name .Source "->" .Destination}}{{end}}'
```

WordPress must also use:

```text
wordpress_data -> /var/www/html
```

This is the core FTP bonus requirement.

No separate FTP data volume is required.

---

## 15. Check the physical WordPress data path

Inspect the volume:

```bash
docker volume inspect wordpress_data
```

The project configures the volume with:

```text
device=/home/tsargsya/data/wordpress
```

Check the physical data directly on the VM:

```bash
ls -la /home/tsargsya/data/wordpress
```

The same files are visible from:

```text
FTP container       /var/www/html
WordPress container /var/www/html
NGINX container     /var/www/html read-only
VM host             /home/tsargsya/data/wordpress
```

---

## 16. Prepare a safe curl FTP client configuration

For command-line tests, create a temporary curl configuration without printing
the password:

```bash
FTP_PASSWORD="$(cat secrets/ftp_password.txt)"

cat > /tmp/ftp-curl.conf <<EOF
user = "ftpuser:${FTP_PASSWORD}"
EOF

chmod 600 /tmp/ftp-curl.conf
unset FTP_PASSWORD
```

Do not use `curl -v` with credentials during normal testing because verbose
output may display the FTP password.

Remove the temporary credential file after testing:

```bash
rm -f /tmp/ftp-curl.conf
```

---

## 17. Check FTP authentication and directory listing

List the FTP root:

```bash
curl \
    --fail \
    --show-error \
    --config /tmp/ftp-curl.conf \
    ftp://127.0.0.1/
```

Expected output contains WordPress files and directories:

```text
wp-admin
wp-content
wp-includes
wp-config.php
```

This confirms:

```text
control connection
Unix authentication
FTP root
passive data connection
LIST operation
```

---

## 18. Test an FTP upload and WordPress visibility

Create a harmless temporary file:

```bash
echo 'Inception FTP test' > /tmp/inception-ftp-test.txt
```

Upload it into `wp-content`:

```bash
curl \
    --fail \
    --show-error \
    --config /tmp/ftp-curl.conf \
    --upload-file /tmp/inception-ftp-test.txt \
    ftp://127.0.0.1/wp-content/inception-ftp-test.txt
```

Read the same file through the WordPress container:

```bash
docker exec wordpress cat \
    /var/www/html/wp-content/inception-ftp-test.txt
```

Expected content:

```text
Inception FTP test
```

This proves that FTP and WordPress use the same persistent volume.

---

## 19. Check uploaded file ownership

Inspect numeric ownership from WordPress:

```bash
docker exec wordpress ls -ln \
    /var/www/html/wp-content/inception-ftp-test.txt
```

Expected owner and group:

```text
33 33
```

Check the same file from FTP:

```bash
docker exec ftp ls -ln \
    /var/www/html/wp-content/inception-ftp-test.txt
```

The numeric owner must still be:

```text
33 33
```

This confirms that FTP uploads remain compatible with WordPress permissions.

---

## 20. Test an FTP download

Download the file again:

```bash
rm -f /tmp/inception-ftp-download.txt

curl \
    --fail \
    --show-error \
    --config /tmp/ftp-curl.conf \
    ftp://127.0.0.1/wp-content/inception-ftp-test.txt \
    -o /tmp/inception-ftp-download.txt
```

Compare uploaded and downloaded content:

```bash
cmp \
    /tmp/inception-ftp-test.txt \
    /tmp/inception-ftp-download.txt \
    && echo 'FTP upload/download: OK'
```

Expected result:

```text
FTP upload/download: OK
```

---

## 21. Test FTP with a graphical client

A graphical FTP client such as FileZilla can be used for evaluation.

For the current local configuration:

```text
Host: 127.0.0.1
Port: 21
Protocol: FTP
User: ftpuser
Password: value from secrets/ftp_password.txt
```

After login, the remote root should show the WordPress installation.

A useful demonstration is:

```text
1. Upload a small file into wp-content with FileZilla.
2. Read it from the WordPress container.
3. Check its numeric owner with ls -ln.
4. Delete it again through the FTP client.
```

Example WordPress check:

```bash
docker exec wordpress cat \
    /var/www/html/wp-content/ftp-demo.txt
```

Modern browsers generally do not provide a normal FTP browsing interface.
Use an FTP client or curl to demonstrate the service.

---

## 22. Check the restart policy

Inspect the configured policy:

```bash
docker inspect ftp \
    --format \
    'policy={{.HostConfig.RestartPolicy.Name}} restart={{.RestartCount}} status={{.State.Status}}'
```

Expected policy:

```text
policy=on-failure
```

A normal `docker restart ftp` is not a real crash-recovery test.

To test a real main-process failure, obtain the host PID:

```bash
FTP_OLD_PID="$(docker inspect -f '{{.State.Pid}}' ftp)"
echo "Old PID: $FTP_OLD_PID"
```

Terminate that process from the host namespace:

```bash
sudo kill -9 "$FTP_OLD_PID"
```

Wait for Docker to restart the container:

```bash
sleep 5
```

Check the new PID and restart count:

```bash
FTP_NEW_PID="$(docker inspect -f '{{.State.Pid}}' ftp)"

echo "Old PID: $FTP_OLD_PID"
echo "New PID: $FTP_NEW_PID"

docker inspect ftp \
    --format \
    'restart={{.RestartCount}} status={{.State.Status}}'
```

Expected properties:

```text
old PID and new PID are different
restart count increased
status=running
```

Then repeat an authenticated FTP request to confirm the service recovered.

---

## 23. Check persistence across `make down` and `make`

First create a temporary FTP file in `wp-content`.

Stop the project:

```bash
make down
```

Check that no project containers remain:

```bash
docker compose -f srcs/docker-compose.yml ps
```

The file must still exist on the VM because `make down` does not delete the
persistent WordPress data:

```bash
ls -ln \
    /home/tsargsya/data/wordpress/wp-content/inception-ftp-test.txt
```

Start the project again:

```bash
make
```

After startup, read the same file through FTP again.

This proves:

```text
containers may be removed
persistent WordPress data remains
new FTP container sees the same data
```

---

## 24. Check a full no-cache rebuild

Run:

```bash
make rebuild
```

This target:

- stops containers;
- preserves the WordPress and MariaDB data directories;
- rebuilds all images with `--no-cache`;
- starts the stack again.

After startup:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Check WordPress:

```bash
curl -k -I https://tsargsya.42.fr
```

Check that a previously uploaded FTP test file still exists and can be read
through FTP.

Then upload a new file after the rebuild and confirm that WordPress can read
it with numeric owner `33:33`.

A successful test proves that the FTP configuration is rebuilt from source
while the shared WordPress data remains persistent.

---

## 25. Check a complete cold start

Warning:

> `make fclean` removes containers, project images, named volumes and
> `/home/tsargsya/data`. Existing MariaDB and WordPress data is destroyed.

Run:

```bash
make fclean
```

Verify that project containers are gone:

```bash
docker compose -f srcs/docker-compose.yml ps
```

The host data directory should also be gone:

```bash
ls -la /home/tsargsya/data
```

A `No such file or directory` result is expected after `fclean`.

Start from scratch:

```bash
make
```

Wait for initialization and check all services:

```bash
sleep 10
docker compose -f srcs/docker-compose.yml ps
```

Check WordPress:

```bash
curl -k -I https://tsargsya.42.fr
```

Expected result includes:

```text
HTTP/1.1 200 OK
```

Recreate `/tmp/ftp-curl.conf` if necessary and list the new FTP root:

```bash
curl \
    --fail \
    --show-error \
    --config /tmp/ftp-curl.conf \
    ftp://127.0.0.1/
```

The new WordPress installation must be visible.

Upload a new file and confirm from WordPress:

```bash
echo 'FTP works after cold start' > /tmp/ftp-cold-start.txt

curl \
    --fail \
    --show-error \
    --config /tmp/ftp-curl.conf \
    --upload-file /tmp/ftp-cold-start.txt \
    ftp://127.0.0.1/wp-content/ftp-cold-start.txt

docker exec wordpress cat \
    /var/www/html/wp-content/ftp-cold-start.txt

docker exec wordpress ls -ln \
    /var/www/html/wp-content/ftp-cold-start.txt
```

Expected owner:

```text
33 33
```

`make re` performs the equivalent destructive cycle because the Makefile runs
`fclean` and then `all`.

---

## 26. Common FTP errors

### `530 Login incorrect`

Meaning:

```text
The FTP server rejected the supplied username or password.
```

Check:

```text
FTP_USER
/run/secrets/ftp_password
ftpuser account
/tmp/ftp-curl.conf or graphical client credentials
```

If the secret was regenerated, recreate any temporary curl configuration that
contains the old password.

### Login works but LIST or upload hangs

Meaning:

```text
The control connection works but the passive data connection cannot be made.
```

Check:

```text
FTP_PASV_ADDRESS
FTP_PASV_MIN_PORT
FTP_PASV_MAX_PORT
PassivePorts in generated proftpd.conf
Compose published passive ports
firewall/network path
```

### `Connection refused` on port 21

Check:

```text
FTP container state
ProFTPD logs
Port 21 in generated configuration
Docker port mapping
host port conflicts
```

### `Permission denied` during upload

Check numeric ownership and permissions:

```bash
docker exec ftp id ftpuser

docker exec ftp ls -ldn /var/www/html

docker exec wordpress ls -ldn /var/www/html
```

The FTP user must have UID/GID `33:33` and the shared WordPress path must be
writable for that identity.

### ProFTPD configuration error

Validate the generated configuration:

```bash
docker exec ftp \
    proftpd -t -c /etc/proftpd/proftpd.conf
```

Inspect environment substitution:

```bash
docker exec ftp cat /etc/proftpd/proftpd.conf
```

### FTP works locally but not from another machine

The current passive address is:

```text
127.0.0.1
```

That address refers to the loopback interface from the client's point of view.
A remote client normally needs the VM's reachable IP address instead.

Update `FTP_PASV_ADDRESS` and ensure the published passive ports are reachable
from the client.

### Uploaded files have the wrong owner

Check with numeric IDs:

```bash
docker exec ftp ls -ln /var/www/html/wp-content

docker exec wordpress ls -ln /var/www/html/wp-content
```

The important value is `33:33`, not the displayed username.

---

## 27. Compact FTP health check

Prepare `/tmp/ftp-curl.conf` first, then run:

```bash
printf '\n=== FTP container ===\n'
docker compose -f srcs/docker-compose.yml ps ftp

printf '\n=== FTP process ===\n'
docker top ftp -eo pid,ppid,user,comm,args

printf '\n=== FTP user ===\n'
docker exec ftp id ftpuser

printf '\n=== Generated configuration ===\n'
docker exec ftp grep -E \
    '^(Port|DefaultRoot|PassivePorts|MasqueradeAddress)' \
    /etc/proftpd/proftpd.conf

printf '\n=== ProFTPD syntax ===\n'
docker exec ftp \
    proftpd -t -c /etc/proftpd/proftpd.conf

printf '\n=== FTP root listing ===\n'
curl \
    --fail \
    --show-error \
    --config /tmp/ftp-curl.conf \
    ftp://127.0.0.1/

printf '\n=== Shared volume ===\n'
docker inspect ftp \
    --format '{{range .Mounts}}{{println .Name "->" .Destination}}{{end}}'

printf '\n=== Restart policy ===\n'
docker inspect ftp \
    --format \
    'policy={{.HostConfig.RestartPolicy.Name}} restart={{.RestartCount}} status={{.State.Status}}'
```

Expected important results:

```text
ftp container: Up
main process: proftpd
ftpuser: UID/GID 33:33
Port: 21
DefaultRoot: ~
PassivePorts: 21000 21010
MasqueradeAddress: 127.0.0.1
ProFTPD syntax check: successful
FTP root: WordPress files visible
shared volume: wordpress_data -> /var/www/html
restart policy: on-failure
```

---

## 28. Final FTP checklist

```text
Custom Debian-based FTP image                    OK
Separate FTP container                          OK
ProFTPD installed from Debian packages          OK
ProFTPD runs in standalone foreground mode      OK
Entrypoint validates required environment       OK
Entrypoint validates the FTP password secret    OK
FTP password is not stored in Git               OK
Configuration generated with envsubst           OK
ProFTPD is PID 1                                OK
FTP control port 21 published                    OK
Passive ports 21000-21010 published             OK
Passive mode configured                         OK
Unix authentication configured                  OK
FTP user exists                                 OK
FTP user UID/GID is 33:33                       OK
FTP user home is /var/www/html                   OK
FTP user is jailed to its home                   OK
wordpress_data mounted at /var/www/html          OK
FTP and WordPress share the same volume          OK
FTP directory listing works                     OK
FTP upload works                                OK
FTP download works                              OK
Uploaded files are visible to WordPress          OK
Uploaded files keep numeric owner 33:33          OK
Restart policy works after a real crash          OK
make down -> make preserves FTP data             OK
make rebuild works                              OK
make fclean -> make cold start works             OK
WordPress still returns HTTP 200 after tests     OK
```

---

## Cleanup after manual tests

Remove temporary FTP files from the WordPress volume:

```bash
docker exec wordpress rm -f \
    /var/www/html/wp-content/inception-ftp-test.txt \
    /var/www/html/wp-content/ftp-cold-start.txt
```

Remove local temporary files:

```bash
rm -f \
    /tmp/inception-ftp-test.txt \
    /tmp/inception-ftp-download.txt \
    /tmp/ftp-cold-start.txt \
    /tmp/ftp-curl.conf
```

Finish by checking the repository:

```bash
git status
```

No password file or temporary FTP test file should be tracked by Git.

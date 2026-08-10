## What NGINX is

NGINX is a web server and reverse proxy.

It accepts client connections, performs TLS termination, selects the correct
virtual host, and forwards requests to the appropriate internal service.

## Role in this project

NGINX is the only externally accessible service.

It publishes:

```text
443/tcp
```

It handles HTTPS requests for:

```text
tsargsya.42.fr
adminer.tsargsya.42.fr
```

Requests are forwarded through FastCGI:

```text
tsargsya.42.fr
→ wordpress:9000

adminer.tsargsya.42.fr
→ adminer:9000
```

NGINX does not execute PHP itself.

PHP is executed by PHP-FPM inside the WordPress or Adminer container.

## Important project properties

```text
Service name: nginx
Internal port: 443
Published port: 443
TLS versions: TLS 1.2 and TLS 1.3
WordPress upstream: wordpress:9000
Adminer upstream: adminer:9000
Persistent volume: none
```

# NGINX Troubleshooting Cheat Sheet

Use the checks in this order:

```text
Container → Logs → Process → Configuration → TLS → Port → Domain → Network → Files → FastCGI → HTTP Response
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
nginx   Up   0.0.0.0:443->443/tcp
```

Useful states:

- `Up` — the container's main process is running.
- `Restarting` — the entrypoint or NGINX repeatedly exits with an error.
- `Exited (1)` — the container stopped with an error.
- `Exited (0)` — the container stopped normally.

Important:

> `Up` means that the main process is running. It does not guarantee that TLS, FastCGI, WordPress, or domain resolution work correctly.

Only NGINX should publish a port on the VM:

```text
nginx      443
wordpress  internal 9000 only
mariadb    internal 3306 only
```

---

## 2. Read the NGINX logs

```bash
docker logs nginx
```

Show only the last 100 lines:

```bash
docker logs --tail=100 nginx
```

Follow logs in real time:

```bash
docker logs -f nginx
```

During a successful startup, expected messages include:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Common error categories:

- missing `DOMAIN_NAME`;
- missing configuration template;
- missing TLS certificate;
- missing private key;
- certificate and private key do not match;
- invalid NGINX syntax;
- Docker DNS cannot resolve `wordpress`;
- PHP-FPM is unavailable;
- incorrect FastCGI script path;
- permission denied while reading mounted files.

Common runtime errors:

```text
connect() failed (111: Connection refused) while connecting to upstream
```

Meaning:

```text
NGINX resolved WordPress, but PHP-FPM is not accepting connections on port 9000.
```

```text
host not found in upstream "wordpress"
```

Meaning:

```text
Docker DNS cannot resolve the WordPress service name,
or the containers are not in the same Docker network.
```

```text
Primary script unknown
```

Meaning:

```text
PHP-FPM received an incorrect SCRIPT_FILENAME,
or NGINX and WordPress do not see the same files under /var/www/html.
```

Stop live log output with:

```text
Ctrl + C
```

---

## 3. Check the main process

Show the command running as PID 1:

```bash
docker exec nginx sh -c '
    printf "PID 1: "
    tr "\0" " " < /proc/1/cmdline
    echo
'
```

Expected result:

```text
PID 1: nginx -g daemon off;
```

The Dockerfile provides:

```dockerfile
CMD ["nginx", "-g", "daemon off;"]
```

The entrypoint finishes with:

```sh
exec "$@"
```

Therefore, NGINX replaces the entrypoint process and becomes PID 1.

Inspect all NGINX processes:

```bash
docker top nginx
```

Expected process types:

```text
nginx: master process
nginx: worker process
```

`daemon off;` keeps NGINX in the foreground so Docker can correctly monitor and stop it.

---

## 4. Validate the NGINX configuration

Run:

```bash
docker exec nginx nginx -t
```

Expected result:

```text
syntax is ok
test is successful
```

This confirms that:

- NGINX configuration syntax is valid;
- the certificate can be read;
- the private key can be read;
- the certificate and key can be loaded together;
- included configuration files exist.

Print the complete active configuration:

```bash
docker exec nginx nginx -T
```

Show only the generated project server block:

```bash
docker exec nginx cat /etc/nginx/conf.d/default.conf
```

Expected important settings:

```nginx
listen 443 ssl default_server;
listen [::]:443 ssl default_server;

server_name tsargsya.42.fr;

root /var/www/html;

ssl_protocols TLSv1.2 TLSv1.3;

fastcgi_pass wordpress:9000;
```

Important:

> The active file is `/etc/nginx/conf.d/default.conf`. The file under `/etc/nginx/templates` is only the source template.

---

## 5. Check template substitution

Inspect the source template:

```bash
docker exec nginx cat \
    /etc/nginx/templates/default.conf.template
```

Expected template value:

```nginx
server_name ${DOMAIN_NAME};
```

Inspect the rendered configuration:

```bash
docker exec nginx grep -n \
    'server_name' \
    /etc/nginx/conf.d/default.conf
```

Expected result:

```text
server_name tsargsya.42.fr;
```

Check the environment variable inside the container:

```bash
docker exec nginx printenv DOMAIN_NAME
```

Expected result:

```text
tsargsya.42.fr
```

The entrypoint renders the configuration with:

```sh
envsubst '${DOMAIN_NAME}'
```

Only `DOMAIN_NAME` is substituted.

This is important because the NGINX configuration also contains native NGINX variables:

```text
$uri
$args
$document_root
$fastcgi_script_name
```

They must not be replaced by the shell.

---

## 6. Check the TLS files inside NGINX

Check that the certificate and private key exist:

```bash
docker exec nginx ls -l \
    /etc/nginx/ssl/inception.crt \
    /etc/nginx/ssl/inception.key
```

Expected files:

```text
/etc/nginx/ssl/inception.crt
/etc/nginx/ssl/inception.key
```

The certificate should be readable by NGINX.

The private key must not be publicly writable.

Check that both files are non-empty:

```bash
docker exec nginx sh -c '
    test -s /etc/nginx/ssl/inception.crt \
        && echo "Certificate: OK"

    test -s /etc/nginx/ssl/inception.key \
        && echo "Private key: OK"
'
```

Expected result:

```text
Certificate: OK
Private key: OK
```

---

## 7. Check TLS mounts

Inspect NGINX mounts:

```bash
docker inspect nginx \
    --format '{{range .Mounts}}{{println .Destination "RW=" .RW "Source=" .Source}}{{end}}'
```

Expected destinations:

```text
/etc/nginx/ssl/inception.crt
/etc/nginx/ssl/inception.key
/var/www/html
```

Expected access mode:

```text
RW=false
```

for:

- the TLS certificate;
- the private key;
- the WordPress volume inside NGINX.

Test that the private key mount is read-only:

```bash
docker exec nginx sh -c '
    echo test >> /etc/nginx/ssl/inception.key
'
```

Expected error:

```text
Read-only file system
```

Do not modify or delete the mounted TLS files from inside the container.

---

## 8. Inspect the certificate on the VM

Show certificate information:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -subject \
    -issuer \
    -dates
```

Expected domain information should include:

```text
CN = tsargsya.42.fr
```

Check the Subject Alternative Name:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -ext subjectAltName
```

Expected result:

```text
DNS:tsargsya.42.fr
```

Check whether the certificate is currently valid:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkend 0
```

Expected result:

```text
Certificate will not expire
```

Check that it matches the configured domain:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -noout \
    -checkhost tsargsya.42.fr
```

Expected result:

```text
Certificate matches hostname tsargsya.42.fr
```

---

## 9. Check that the certificate and private key match

Extract the public key from the certificate:

```bash
openssl x509 \
    -in certificates/inception.crt \
    -pubkey \
    -noout \
    > /tmp/inception-cert-public-key.pem
```

Extract the public key derived from the private key:

```bash
openssl pkey \
    -in certificates/inception.key \
    -pubout \
    > /tmp/inception-private-public-key.pem
```

Compare them:

```bash
diff \
    /tmp/inception-cert-public-key.pem \
    /tmp/inception-private-public-key.pem
```

Expected result:

```text
No output
```

No output means that both public keys are identical and the files form one TLS pair.

Remove temporary files:

```bash
rm -f \
    /tmp/inception-cert-public-key.pem \
    /tmp/inception-private-public-key.pem
```

---

## 10. Understand the browser certificate warning

The project uses a self-signed certificate.

A browser may display a warning such as:

```text
Your connection is not private
```

or:

```text
The certificate authority is invalid
```

This is expected because the certificate was not signed by a public certificate authority trusted by the browser.

Important:

> A browser trust warning does not mean that TLS encryption is disabled.

The connection can still be encrypted while the certificate remains locally untrusted.

For command-line tests, use:

```bash
curl -k https://tsargsya.42.fr/
```

`-k` disables certificate authority verification for that command. It does not disable TLS encryption.

---

## 11. Test TLS 1.2

Run:

```bash
openssl s_client \
    -brief \
    -connect localhost:443 \
    -servername tsargsya.42.fr \
    -tls1_2 \
    </dev/null
```

Expected important output:

```text
Protocol version: TLSv1.2
```

A self-signed verification warning is expected unless the certificate is explicitly trusted.

Test while trusting the project certificate:

```bash
openssl s_client \
    -brief \
    -connect localhost:443 \
    -servername tsargsya.42.fr \
    -tls1_2 \
    -CAfile certificates/inception.crt \
    </dev/null
```

Expected verification:

```text
Verification: OK
```

---

## 12. Test TLS 1.3

Run:

```bash
openssl s_client \
    -brief \
    -connect localhost:443 \
    -servername tsargsya.42.fr \
    -tls1_3 \
    </dev/null
```

Expected important output:

```text
Protocol version: TLSv1.3
```

Test while trusting the project certificate:

```bash
openssl s_client \
    -brief \
    -connect localhost:443 \
    -servername tsargsya.42.fr \
    -tls1_3 \
    -CAfile certificates/inception.crt \
    </dev/null
```

Expected verification:

```text
Verification: OK
```

---

## 13. Confirm that TLS 1.0 and TLS 1.1 are rejected

Modern OpenSSL may refuse to attempt old protocols at its default security level.

Force a TLS 1.0 attempt only for this client command:

```bash
openssl s_client \
    -brief \
    -connect localhost:443 \
    -servername tsargsya.42.fr \
    -tls1 \
    -cipher 'DEFAULT:@SECLEVEL=0' \
    </dev/null
```

Expected result:

```text
tlsv1 alert protocol version
SSL alert number 70
```

Test TLS 1.1:

```bash
openssl s_client \
    -brief \
    -connect localhost:443 \
    -servername tsargsya.42.fr \
    -tls1_1 \
    -cipher 'DEFAULT:@SECLEVEL=0' \
    </dev/null
```

Expected result:

```text
tlsv1 alert protocol version
SSL alert number 70
```

Meaning:

```text
The client attempted the legacy TLS version.
NGINX received the attempt.
NGINX rejected it with a protocol-version alert.
```

Do not confuse this with:

```text
no protocols available
```

That message usually means that the local OpenSSL client blocked the old protocol before contacting NGINX.

---

## 14. Check the published port

Inspect published ports:

```bash
docker compose -f srcs/docker-compose.yml ps
```

Expected NGINX mapping:

```text
0.0.0.0:443->443/tcp
[::]:443->443/tcp
```

Check only the NGINX port:

```bash
docker port nginx
```

Expected result:

```text
443/tcp -> 0.0.0.0:443
443/tcp -> [::]:443
```

Check the host listening socket:

```bash
ss -lnt | grep ':443'
```

Expected listening address:

```text
0.0.0.0:443
```

or:

```text
[::]:443
```

Important:

> `EXPOSE 443` in the Dockerfile documents the container port. The Compose `ports` section publishes it on the VM.

---

## 15. Confirm that port 80 is not published

Run:

```bash
docker port nginx
```

There should be no port `80` mapping.

Test from the VM:

```bash
curl -I http://tsargsya.42.fr/
```

Expected result:

```text
Connection refused
```

or another connection failure.

The project accepts external traffic through HTTPS on port 443 only.

---

## 16. Check local domain resolution

Check the project domain:

```bash
getent hosts tsargsya.42.fr
```

Expected result:

```text
127.0.0.1 tsargsya.42.fr
```

Inspect the `/etc/hosts` entry:

```bash
grep -n 'tsargsya.42.fr' /etc/hosts
```

Expected mapping:

```text
127.0.0.1    tsargsya.42.fr    # Inception
```

Check that only one project mapping exists:

```bash
grep -c 'tsargsya.42.fr' /etc/hosts
```

Expected result:

```text
1
```

The mapping is prepared by:

```text
srcs/tools/configure_domain.sh
```

The script:

- reads `DOMAIN_NAME` from `srcs/.env`;
- detects an existing correct mapping;
- avoids duplicate entries;
- rejects conflicting IP mappings.

Important:

> The script modifies the hosts file of the machine where `make` runs. It cannot modify the hosts file of another operating system, such as Windows outside the VM.

---

## 17. Check the domain environment source

Inspect the source value:

```bash
cat srcs/.env
```

Expected result:

```text
DOMAIN_NAME=tsargsya.42.fr
```

Check the value passed to NGINX:

```bash
docker exec nginx printenv DOMAIN_NAME
```

Check the value stored by WordPress:

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html option get siteurl
```

```bash
docker exec -u www-data wordpress \
    wp --path=/var/www/html option get home
```

Expected result for both:

```text
https://tsargsya.42.fr
```

These values should remain consistent:

```text
srcs/.env
TLS certificate
/etc/hosts
NGINX server_name
WordPress siteurl
WordPress home
```

---

## 18. Understand redirects from `localhost`

The NGINX server block is configured as:

```nginx
listen 443 ssl default_server;
```

Therefore, a request to:

```text
https://localhost
```

may still be accepted by this server block.

However, WordPress is installed with:

```text
https://tsargsya.42.fr
```

as its canonical address.

WordPress links and redirects will therefore point to:

```text
https://tsargsya.42.fr
```

This is expected.

Use:

```text
https://tsargsya.42.fr
```

instead of:

```text
https://localhost
```

for normal browser testing.

---

## 19. Check the Docker network

List the project network:

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

All three containers should appear:

```text
mariadb
wordpress
nginx
```

If NGINX is missing from the network, it cannot resolve or reach WordPress.

---

## 20. Check Docker DNS from NGINX

Check that the WordPress service name resolves:

```bash
docker exec nginx getent hosts wordpress
```

Expected result:

```text
<container-ip> wordpress
```

The NGINX upstream is:

```text
wordpress:9000
```

Do not use:

```text
localhost:9000
127.0.0.1:9000
```

Inside the NGINX container, `localhost` refers to NGINX itself, not WordPress.

Docker DNS resolves the service name:

```text
wordpress
```

to the current internal IP of the WordPress container.

---

## 21. Check PHP-FPM from the WordPress side

Validate PHP-FPM:

```bash
docker exec wordpress php-fpm8.2 -t
```

Expected result:

```text
configuration file ... test is successful
```

Check the configured listening port:

```bash
docker exec wordpress grep -E '^listen[[:space:]]*=' \
    /etc/php/8.2/fpm/pool.d/www.conf
```

Expected result:

```text
listen = 9000
```

Check the WordPress PID 1 command:

```bash
docker exec wordpress sh -c '
    tr "\0" " " < /proc/1/cmdline
    echo
'
```

Expected result:

```text
php-fpm8.2 -F
```

If NGINX returns `502 Bad Gateway`, check WordPress and PHP-FPM before changing the NGINX configuration.

---

## 22. Check the shared WordPress files

List important files from NGINX:

```bash
docker exec nginx sh -c '
    ls -ld \
        /var/www/html \
        /var/www/html/index.php \
        /var/www/html/wp-admin \
        /var/www/html/wp-content \
        /var/www/html/wp-includes \
        /var/www/html/wp-login.php
'
```

Expected paths:

```text
/var/www/html/index.php
/var/www/html/wp-admin
/var/www/html/wp-content
/var/www/html/wp-includes
/var/www/html/wp-login.php
```

List the same files from WordPress:

```bash
docker exec wordpress sh -c '
    ls -ld \
        /var/www/html \
        /var/www/html/index.php \
        /var/www/html/wp-admin \
        /var/www/html/wp-content \
        /var/www/html/wp-includes \
        /var/www/html/wp-login.php
'
```

Both containers must see the same filesystem structure under:

```text
/var/www/html
```

NGINX requires the shared files to:

- test whether a requested file exists;
- serve static assets;
- build the correct PHP script path.

---

## 23. Check the WordPress mount is read-only in NGINX

Inspect the mount:

```bash
docker inspect nginx \
    --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}Destination={{.Destination}} RW={{.RW}} Source={{.Source}}{{end}}{{end}}'
```

Expected value:

```text
RW=false
```

Test the restriction:

```bash
docker exec nginx sh -c '
    touch /var/www/html/nginx-write-test
'
```

Expected error:

```text
Read-only file system
```

NGINX should read and serve WordPress files, not modify them.

---

## 24. Check static file handling

Choose an existing static file:

```bash
docker exec nginx test -f \
    /var/www/html/wp-includes/css/dashicons.css \
    && echo "Static file exists"
```

Request it from the VM:

```bash
curl -k -I \
    https://tsargsya.42.fr/wp-includes/css/dashicons.css
```

Expected result:

```text
HTTP/1.1 200 OK
```

This confirms that:

- the domain resolves;
- TLS works;
- NGINX sees the WordPress volume;
- NGINX can serve a static file directly.

---

## 25. Check PHP request handling

Request the WordPress front controller:

```bash
curl -k -I \
    https://tsargsya.42.fr/index.php
```

Expected result:

```text
HTTP/1.1 200 OK
```

or a valid WordPress redirect.

Request the login page:

```bash
curl -k -I \
    https://tsargsya.42.fr/wp-login.php
```

Expected result:

```text
HTTP/1.1 200 OK
```

A successful PHP response confirms that:

- NGINX matched the PHP location;
- the file passed `try_files`;
- Docker DNS resolved `wordpress`;
- PHP-FPM accepted FastCGI;
- `SCRIPT_FILENAME` was correct;
- WordPress generated a response.

---

## 26. Check `SCRIPT_FILENAME`

Inspect the active setting:

```bash
docker exec nginx grep -A3 -B3 \
    'SCRIPT_FILENAME' \
    /etc/nginx/conf.d/default.conf
```

Expected configuration:

```nginx
fastcgi_param SCRIPT_FILENAME
    $document_root$fastcgi_script_name;
```

For:

```text
/wp-login.php
```

the resulting path should be:

```text
/var/www/html/wp-login.php
```

Possible error:

```text
Primary script unknown
```

Check:

- whether the file exists in both containers;
- whether both containers mount WordPress at `/var/www/html`;
- whether `root` is `/var/www/html`;
- whether `SCRIPT_FILENAME` uses the correct variables.

---

## 27. Check HTTPS information passed to PHP-FPM

Inspect:

```bash
docker exec nginx grep -n \
    'fastcgi_param HTTPS' \
    /etc/nginx/conf.d/default.conf
```

Expected result:

```nginx
fastcgi_param HTTPS on;
```

TLS terminates at NGINX.

PHP-FPM receives FastCGI traffic through the internal Docker network and does not directly see the original TLS connection.

This parameter tells WordPress:

```text
The original browser request used HTTPS.
```

Without it, WordPress may generate:

- `http://` links;
- incorrect redirects;
- login redirect loops;
- mixed-content URLs.

---

## 28. Test the main website

Request headers:

```bash
curl -k -I https://tsargsya.42.fr/
```

Expected result:

```text
HTTP/1.1 200 OK
```

Request the page body:

```bash
curl -k https://tsargsya.42.fr/ | head
```

Expected output should contain HTML.

Show the TLS handshake and HTTP exchange:

```bash
curl -k -v https://tsargsya.42.fr/ -o /dev/null
```

Useful information includes:

```text
Connected to tsargsya.42.fr
SSL connection using TLSv1.2 or TLSv1.3
HTTP/1.1 200 OK
```

---

## 29. Diagnose `502 Bad Gateway`

First check NGINX logs:

```bash
docker logs --tail=100 nginx
```

Then check WordPress:

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs --tail=100 wordpress
```

Validate PHP-FPM:

```bash
docker exec wordpress php-fpm8.2 -t
```

Check Docker DNS:

```bash
docker exec nginx getent hosts wordpress
```

Check active upstream:

```bash
docker exec nginx grep -n \
    'fastcgi_pass' \
    /etc/nginx/conf.d/default.conf
```

Expected upstream:

```text
wordpress:9000
```

Common causes:

```text
WordPress container is stopped
→ start or repair WordPress

PHP-FPM failed to start
→ inspect WordPress logs and PHP-FPM configuration

Incorrect upstream hostname
→ use wordpress, not localhost

Incorrect port
→ use port 9000

Containers are in different networks
→ attach both services to the inception network
```

---

## 30. Diagnose `404 Not Found`

Check whether the requested file exists:

```bash
docker exec nginx test -e \
    /var/www/html/path-to-file \
    && echo "File exists" \
    || echo "File does not exist"
```

For PHP requests, the configuration uses:

```nginx
try_files $uri =404;
```

Therefore, a missing `.php` file is intentionally rejected before reaching PHP-FPM.

For WordPress pretty URLs, the root location uses:

```nginx
try_files $uri $uri/ /index.php?$args;
```

A URL such as:

```text
/some-wordpress-page
```

does not need to exist as a physical file. It should fall back to `index.php`.

Check the active configuration if pretty URLs unexpectedly return 404.

---

## 31. Diagnose certificate startup errors

Possible error:

```text
cannot load certificate
```

Check:

```bash
ls -l \
    certificates/inception.crt \
    certificates/inception.key
```

Run the certificate preparation script:

```bash
./srcs/tools/generate_certificates.sh
```

Then rebuild/recreate NGINX:

```bash
docker compose -f srcs/docker-compose.yml \
    up -d --build --force-recreate nginx
```

Possible error:

```text
key values mismatch
```

Meaning:

```text
The certificate and private key do not belong to the same pair.
```

The generator should detect this and recreate both files together.

Do not manually replace only one of the two TLS files.

---

## 32. Check certificate persistence

Record current hashes:

```bash
sha256sum \
    certificates/inception.crt \
    certificates/inception.key \
    > /tmp/inception-tls-before.txt
```

Recreate the containers:

```bash
docker compose -f srcs/docker-compose.yml down
make
```

Record the hashes again:

```bash
sha256sum \
    certificates/inception.crt \
    certificates/inception.key \
    > /tmp/inception-tls-after.txt
```

Compare:

```bash
diff \
    /tmp/inception-tls-before.txt \
    /tmp/inception-tls-after.txt
```

Expected result:

```text
No output
```

This confirms that container recreation does not regenerate a valid certificate pair.

Remove temporary files:

```bash
rm -f \
    /tmp/inception-tls-before.txt \
    /tmp/inception-tls-after.txt
```

---

## 33. Check that OpenSSL is not installed in NGINX

Run:

```bash
docker exec nginx sh -c '
    command -v openssl \
        && echo "OpenSSL is installed" \
        || echo "OpenSSL is not installed"
'
```

Expected result:

```text
OpenSSL is not installed
```

The host prepares the certificate.

The NGINX container only reads and uses it.

---

## 34. Check the resolved Compose configuration

Run:

```bash
docker compose -f srcs/docker-compose.yml config
```

Use this command to verify:

- NGINX build context;
- image name;
- container name;
- environment file;
- dependency on WordPress;
- port `443:443`;
- WordPress read-only volume;
- certificate mounts;
- private-key mount;
- Docker network;
- restart policy.

This shows the final Compose model after YAML processing.

---

## 35. Restart NGINX

Normal restart:

```bash
docker compose -f srcs/docker-compose.yml restart nginx
```

Then check:

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs --tail=100 nginx
docker exec nginx nginx -t
```

A restart does not rebuild the image.

---

## 36. Rebuild and recreate NGINX

Use after changing:

- the Dockerfile;
- the entrypoint;
- the NGINX configuration template.

Run:

```bash
docker compose -f srcs/docker-compose.yml \
    up -d --build --force-recreate nginx
```

Then check:

```bash
docker logs --tail=100 nginx
docker exec nginx nginx -t
curl -k -I https://tsargsya.42.fr/
```

Important:

> A plain container restart does not apply files that were copied into the image during build.

---

## 37. Understand the preparation flow

Running:

```bash
make
```

performs:

```text
Create MariaDB host directory
Create WordPress host directory
Configure the local project domain
Generate or validate the TLS certificate pair
Build and start the Compose services
```

The relevant Makefile targets are:

```makefile
all: prepare
    docker compose ... up --build -d
```

and:

```makefile
prepare:
    mkdir -p ...
    ./srcs/tools/configure_domain.sh
    ./srcs/tools/generate_certificates.sh
```

If domain or certificate preparation fails, Compose should not start.

---

# Fast Diagnostic Path

For a quick investigation, start with:

```bash
docker compose -f srcs/docker-compose.yml ps
docker logs --tail=100 nginx
docker exec nginx nginx -t
docker exec nginx getent hosts wordpress
docker exec nginx cat /etc/nginx/conf.d/default.conf
getent hosts tsargsya.42.fr
curl -k -I https://tsargsya.42.fr/
```

Check mounts:

```bash
docker inspect nginx \
    --format '{{range .Mounts}}{{println .Destination "RW=" .RW "Source=" .Source}}{{end}}'
```

Check PHP-FPM:

```bash
docker exec wordpress php-fpm8.2 -t
```

Check TLS:

```bash
openssl s_client \
    -brief \
    -connect localhost:443 \
    -servername tsargsya.42.fr \
    -tls1_2 \
    </dev/null
```

---

# Common Error Map

```text
NGINX container is Restarting
→ read docker logs nginx
→ run nginx -t

DOMAIN_NAME is not set
→ check srcs/.env
→ check the NGINX env_file entry

cannot read certificate or private key
→ check host files
→ check Compose mounts
→ check file permissions

certificate/key mismatch
→ run srcs/tools/generate_certificates.sh
→ recreate NGINX

host not found in upstream "wordpress"
→ check Docker network
→ check service name
→ check Docker DNS

connect() failed (111: Connection refused)
→ WordPress exists, but PHP-FPM is not ready on port 9000

502 Bad Gateway
→ check WordPress logs
→ validate PHP-FPM
→ check wordpress:9000

Primary script unknown
→ check SCRIPT_FILENAME
→ check shared /var/www/html volume
→ check that the requested PHP file exists

404 for a PHP file
→ the file failed try_files $uri =404

localhost redirects to tsargsya.42.fr
→ expected WordPress canonical URL behavior
→ open the project through tsargsya.42.fr

tsargsya.42.fr does not resolve
→ check /etc/hosts
→ run srcs/tools/configure_domain.sh

browser reports an untrusted certificate
→ expected for a self-signed certificate

TLS 1.0 or TLS 1.1 is rejected
→ expected project behavior

port 443 is unreachable
→ check Compose ports
→ check ss -lnt
→ check NGINX container state
```

---

# Troubleshooting Logic to Remember

```text
1. Is the NGINX container running?
2. What do the NGINX logs say?
3. Is NGINX the PID 1 process?
4. Does nginx -t succeed?
5. Was the template rendered with the correct domain?
6. Can NGINX read the certificate and private key?
7. Do the certificate and private key match?
8. Are only TLS 1.2 and TLS 1.3 accepted?
9. Is port 443 published on the VM?
10. Does tsargsya.42.fr resolve to 127.0.0.1?
11. Are NGINX and WordPress in the same Docker network?
12. Does the hostname wordpress resolve from NGINX?
13. Is PHP-FPM listening on wordpress:9000?
14. Do NGINX and WordPress see the same /var/www/html files?
15. Is the WordPress mount read-only inside NGINX?
16. Does a static file return 200?
17. Does a PHP request return a valid WordPress response?
```

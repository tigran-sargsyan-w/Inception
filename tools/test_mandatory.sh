#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/srcs/docker-compose.yml"
ENV_FILE="$PROJECT_ROOT/srcs/.env"
DATABASE_ENV_FILE="$PROJECT_ROOT/srcs/environment/database.env"
WORDPRESS_ENV_FILE="$PROJECT_ROOT/srcs/environment/wordpress.env"
CERTIFICATE_FILE="$PROJECT_ROOT/certificates/inception.crt"
PRIVATE_KEY_FILE="$PROJECT_ROOT/certificates/inception.key"
DATA_DIR="/home/$(id -un)/data"
MARIADB_DATA_DIR="$DATA_DIR/mariadb"
WORDPRESS_DATA_DIR="$DATA_DIR/wordpress"
CONTAINERS=(mariadb wordpress nginx)
SECRET_FILES=(
  "$PROJECT_ROOT/secrets/db_root_password.txt"
  "$PROJECT_ROOT/secrets/db_password.txt"
  "$PROJECT_ROOT/secrets/wp_admin_password.txt"
  "$PROJECT_ROOT/secrets/wp_user_password.txt"
)

MODE="${1:-help}"
shift 2>/dev/null || true
VERBOSE=1
ASSUME_YES=0
NO_COLOR_FLAG=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --summary) VERBOSE=0 ;;
    --yes) ASSUME_YES=1 ;;
    --no-color) NO_COLOR_FLAG=1 ;;
    -h|--help) MODE=help ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

usage() {
  cat <<'USAGE'
Usage:
  ./tools/test_mandatory.sh <mode> [options]

Modes:
  list          List all test modes.
  preflight     Tools, environment, secrets, and Compose structure.
  runtime       Containers, PID 1, configs, HTTPS, and ports.
  tls           Certificate and TLS protocol tests.
  wordpress     WordPress installation, options, DB settings, and users.
  mariadb       MariaDB database, users, grants, runtime, and marker.
  network       Bridge network, DNS, internal path, and shared volume.
  persistence   File + database persistence through make down / make.
  restart       Real main-process crash and automatic restart tests.
  security      Git, secrets, tags, base images, and forbidden patterns.
  cold-start    Destructive clean build and cold-start validation.
  full          Complete destructive mandatory acceptance suite.
  help          Show this help.

Options:
  --summary     Show only verdicts and final summary.
  --yes         Skip destructive confirmation for cold-start/full.
  --no-color    Disable colors.
USAGE
}

list_modes() {
  cat <<'LIST'
preflight   - tools, daemon, env, secrets, Compose
runtime     - containers, PID 1, configs, HTTPS, ports
tls         - certificate, hostname, key pair, protocols
wordpress   - install, site options, DB config, users
mariadb     - database, accounts, TCP, grants, marker
network     - bridge network, DNS, service path, shared volume
persistence - make down/make data survival and cleanup
restart     - crash NGINX, WordPress, MariaDB and verify recovery
security    - Git/secrets/history/tags/base images/forbidden patterns
cold-start  - destructive reset, build, initialization and runtime tests
full        - every automated technical mandatory test
LIST
}

case "$MODE" in
  help) usage; exit 0 ;;
  list) list_modes; exit 0 ;;
  preflight|runtime|tls|wordpress|mariadb|network|persistence|restart|security|cold-start|full) ;;
  *) printf 'Unknown mode: %s\n\n' "$MODE" >&2; usage >&2; exit 2 ;;
esac

mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/mandatory-test-$(date '+%Y%m%d-%H%M%S').log"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inception-test.XXXXXX")"

if [ -t 1 ] && [ "$NO_COLOR_FLAG" -eq 0 ] && [ -z "${NO_COLOR+x}" ]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'
else
  RESET=""; BOLD=""; GREEN=""; YELLOW=""; RED=""; CYAN=""
fi

exec > >(tee -a "$LOG_FILE") 2>&1
cd "$PROJECT_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TEST_NO=0
RESULTS=()
OUT=""
RC=0
CURRENT=""
PERSIST_ID=""
POST_ID=""

cleanup() {
  if [ -n "$PERSIST_ID" ] && docker inspect wordpress >/dev/null 2>&1; then
    docker exec -u www-data wordpress rm -f "/var/www/html/wp-content/${PERSIST_ID}.txt" >/dev/null 2>&1 || true
  fi
  if [ -n "$POST_ID" ] && docker inspect wordpress >/dev/null 2>&1; then
    docker exec -u www-data wordpress wp --path=/var/www/html post delete "$POST_ID" --force >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

line() { printf '%s\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'; }
header() {
  CURRENT="$1"
  TEST_NO=$((TEST_NO + 1))
  [ "$VERBOSE" -eq 1 ] || return 0
  printf '\n'; line; printf '%bTEST %d — %s%b\n' "$BOLD" "$TEST_NO" "$CURRENT" "$RESET"; line
}
command_text() { [ "$VERBOSE" -eq 1 ] && printf '\n%bCommand:%b\n  %s\n' "$BOLD" "$RESET" "$1" || true; }
evidence() {
  [ "$VERBOSE" -eq 1 ] || return 0
  printf '\n%bEvidence:%b\n' "$BOLD" "$RESET"
  if [ -n "${1:-}" ]; then printf '%s\n' "$1" | sed 's/^/  /'; else printf '  <no output>\n'; fi
}
expected() { [ "$VERBOSE" -eq 1 ] && printf '\n%bExpected:%b\n%s\n' "$BOLD" "$RESET" "$(printf '%s\n' "$1" | sed 's/^/  /')" || true; }
note() { [ "$VERBOSE" -eq 1 ] && printf '\n%bNote:%b\n%s\n' "$BOLD" "$RESET" "$(printf '%s\n' "$1" | sed 's/^/  /')" || true; }
pass() { PASS_COUNT=$((PASS_COUNT + 1)); RESULTS+=("PASS|$CURRENT|$1"); printf '\n%b[PASS]%b %s\n' "$GREEN" "$RESET" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); RESULTS+=("FAIL|$CURRENT|$1"); printf '\n%b[FAIL]%b %s\n' "$RED" "$RESET" "$1"; }
skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); RESULTS+=("SKIP|$CURRENT|$1"); printf '\n%b[SKIP]%b %s\n' "$YELLOW" "$RESET" "$1"; }

capture() {
  local shown="$1"; shift
  command_text "$shown"
  OUT="$("$@" 2>&1)"; RC=$?
  evidence "$OUT"
  [ "$VERBOSE" -eq 1 ] && printf '\n%bExit code:%b\n  %d\n' "$BOLD" "$RESET" "$RC" || true
}

capture_sh() {
  local shown="$1" code="$2"
  command_text "$shown"
  OUT="$(bash -o pipefail -c "$code" 2>&1)"; RC=$?
  evidence "$OUT"
  [ "$VERBOSE" -eq 1 ] && printf '\n%bExit code:%b\n  %d\n' "$BOLD" "$RESET" "$RC" || true
}

compose() { docker compose -f "$COMPOSE_FILE" "$@"; }
read_env() {
  local key="$1"; shift
  local f v
  for f in "$@"; do
    [ -r "$f" ] || continue
    v="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" "$f" | tail -n 1 | tr -d '\r')"
    if [ -n "$v" ]; then printf '%s\n' "$v"; return 0; fi
  done
  return 1
}
domain() { read_env DOMAIN_NAME "$ENV_FILE"; }
db_name() { read_env MYSQL_DATABASE "$DATABASE_ENV_FILE"; }
db_user() { read_env MYSQL_USER "$DATABASE_ENV_FILE"; }
wp_admin() { read_env WP_ADMIN_USER "$WORDPRESS_ENV_FILE"; }
wp_user() { read_env WP_USER "$WORDPRESS_ENV_FILE"; }

stack_running() {
  local c s
  for c in "${CONTAINERS[@]}"; do
    s="$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || true)"
    [ "$s" = running ] || return 1
  done
}
require_stack() {
  stack_running && return 0
  header 'Running stack required'
  capture 'docker compose -f srcs/docker-compose.yml ps -a' compose ps -a
  expected 'mariadb, wordpress, and nginx are all running'
  fail 'This mode requires a running Inception stack'
  return 1
}
wait_stack() {
  local n=0 c s ok
  while [ "$n" -lt "${1:-90}" ]; do
    ok=1; OUT=""
    for c in "${CONTAINERS[@]}"; do
      s="$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || printf missing)"
      OUT+="$c=$s "
      [ "$s" = running ] || ok=0
    done
    [ "$ok" -eq 1 ] && { RC=0; return 0; }
    sleep 2; n=$((n + 2))
  done
  RC=1; return 1
}
wait_https() {
  local n=0 code=""
  while [ "$n" -lt "${1:-60}" ]; do
    code="$(curl -k -sS --connect-timeout 2 -o /dev/null -w '%{http_code}' "https://$(domain)/" 2>/dev/null || true)"
    [ "$code" = 200 ] && { OUT="HTTPS status=200"; RC=0; return 0; }
    sleep 2; n=$((n + 2))
  done
  OUT="HTTPS status=${code:-connection-failed}"; RC=1; return 1
}

confirm_delete() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  printf '\n%bDESTRUCTIVE TEST WARNING%b\n' "$RED$BOLD" "$RESET"
  printf 'This removes containers, images, volumes, certificates, and all data under:\n  %s\n\n' "$DATA_DIR"
  printf 'Type DELETE ALL DATA to continue: '
  local answer; IFS= read -r answer
  [ "$answer" = 'DELETE ALL DATA' ] || { printf 'Cancelled.\n'; exit 2; }
}

printf '%bInception Mandatory Test Runner%b\n' "$CYAN$BOLD" "$RESET"
printf 'Project root: %s\nMode:         %s\nEvidence log: %s\n' "$PROJECT_ROOT" "$MODE" "$LOG_FILE"

run_preflight() {
  header 'Project layout'
  capture_sh 'check required project files' '
    for f in Makefile srcs/docker-compose.yml srcs/.env srcs/environment/database.env srcs/environment/wordpress.env; do
      if [ -e "$f" ]; then echo "present: $f"; else echo "missing: $f"; exit 1; fi
    done'
  expected 'All required project files are present'
  [ "$RC" -eq 0 ] && pass 'Required project files are present' || fail 'One or more required project files are missing'

  header 'Required command-line tools'
  capture_sh 'print versions for required tools' '
    docker --version
    docker compose version
    python3 --version
    openssl version
    curl --version | head -n 1
    git --version
    make --version | head -n 1'
  expected 'Every required command prints a version and exits successfully'
  [ "$RC" -eq 0 ] && pass 'All required command-line tools are available' || fail 'At least one required tool is unavailable'

  header 'Docker daemon'
  capture 'docker info' docker info
  expected 'Docker returns server information with exit code 0'
  [ "$RC" -eq 0 ] && pass 'Docker daemon is running' || fail 'Docker daemon is unavailable'

  header 'Non-secret environment configuration'
  capture_sh 'print non-secret environment files' '
    echo "--- srcs/.env ---"; cat srcs/.env
    echo "--- database.env ---"; cat srcs/environment/database.env
    echo "--- wordpress.env ---"; cat srcs/environment/wordpress.env'
  expected 'DOMAIN_NAME=tsargsya.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_HOST=mariadb
MARIADB_PORT=3306
WP_TITLE=Inception
WP_ADMIN_USER=tsargsya
WP_USER=writer'
  local h p title
  h="$(read_env MYSQL_HOST "$DATABASE_ENV_FILE" "$WORDPRESS_ENV_FILE" 2>/dev/null || true)"
  p="$(read_env MARIADB_PORT "$DATABASE_ENV_FILE" 2>/dev/null || true)"
  title="$(read_env WP_TITLE "$WORDPRESS_ENV_FILE" 2>/dev/null || true)"
  if [ "$(domain 2>/dev/null || true)" = tsargsya.42.fr ] \
    && [ "$(db_name 2>/dev/null || true)" = wordpress ] \
    && [ "$(db_user 2>/dev/null || true)" = wpuser ] \
    && [ "$h" = mariadb ] && [ "$p" = 3306 ] && [ "$title" = Inception ] \
    && [ "$(wp_admin 2>/dev/null || true)" = tsargsya ] \
    && [ "$(wp_user 2>/dev/null || true)" = writer ]; then
    pass 'Non-secret environment values match the mandatory infrastructure'
  else
    fail 'One or more non-secret environment values are missing or unexpected'
  fi

  header 'Local secret files'
  local ev="" f mode size valid=1
  for f in "${SECRET_FILES[@]}"; do
    if [ -e "$f" ]; then
      mode="$(stat -c '%a' "$f" 2>/dev/null || echo '?')"
      size="$(stat -c '%s' "$f" 2>/dev/null || echo 0)"
      ev+="${f#"$PROJECT_ROOT/"} mode=$mode size=$size bytes"$'\n'
      [ -s "$f" ] || valid=0
      [ "$mode" = 600 ] || valid=0
    else
      ev+="${f#"$PROJECT_ROOT/"} missing"$'\n'; valid=0
    fi
  done
  command_text "stat -c '%a %s %n' secrets/*.txt"; evidence "${ev%$'\n'}"
  expected 'All four secrets exist, are non-empty, and have mode 600'
  note 'Secret values are intentionally never printed'
  [ "$valid" -eq 1 ] && pass 'All required secret files are present and protected' || fail 'A secret is missing, empty, or has unsafe permissions'

  header 'Resolved Compose configuration'
  capture 'docker compose -f srcs/docker-compose.yml config' compose config
  expected 'Compose resolves the complete YAML configuration with exit code 0'
  [ "$RC" -eq 0 ] && pass 'Docker Compose configuration is valid' || fail 'Docker Compose configuration is invalid'

  test_compose_architecture
}

test_compose_architecture() {
  header 'Compose architecture'
  capture_sh 'show resolved services, images, volumes, and networks' '
    echo Services:; docker compose -f srcs/docker-compose.yml config --services
    echo Images:; docker compose -f srcs/docker-compose.yml config --images
    echo Volumes:; docker compose -f srcs/docker-compose.yml config --volumes
    echo Networks:; docker compose -f srcs/docker-compose.yml config --networks'
  expected 'Services: mariadb, nginx, wordpress
Images: mariadb:inception, nginx:inception, wordpress:inception
Volumes: mariadb_data, wordpress_data
Network: inception'
  local services images volumes networks
  services="$(compose config --services 2>/dev/null | sort || true)"
  images="$(compose config --images 2>/dev/null | sort || true)"
  volumes="$(compose config --volumes 2>/dev/null | sort || true)"
  networks="$(compose config --networks 2>/dev/null | sort || true)"
  if [ "$services" = $'mariadb\nnginx\nwordpress' ] \
    && [ "$images" = $'mariadb:inception\nnginx:inception\nwordpress:inception' ] \
    && [ "$volumes" = $'mariadb_data\nwordpress_data' ] \
    && [ "$networks" = inception ]; then
    pass 'Compose declares the expected mandatory architecture'
  else
    fail 'Resolved Compose architecture differs from the expected structure'
  fi
}

run_runtime() {
  require_stack || return

  header 'Container state'
  capture_sh 'show Compose state and detailed container state' '
    docker compose -f srcs/docker-compose.yml ps -a
    echo; echo Detailed state:
    for c in mariadb wordpress nginx; do
      docker inspect --format "{{.Name}} status={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} exit_code={{.State.ExitCode}}" "$c"
    done'
  expected 'All three containers are running; none is Restarting or Exited'
  stack_running && pass 'All mandatory containers are running' || fail 'At least one mandatory container is not running'

  header 'Restart policy configuration'
  capture_sh 'inspect restart policies' '
    for c in mariadb wordpress nginx; do
      docker inspect --format "{{.Name}} policy={{.HostConfig.RestartPolicy.Name}} maximum_retries={{.HostConfig.RestartPolicy.MaximumRetryCount}}" "$c"
    done'
  expected 'Every container uses restart policy on-failure'
  local c valid=1
  for c in "${CONTAINERS[@]}"; do [ "$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$c" 2>/dev/null || true)" = on-failure ] || valid=0; done
  [ "$valid" -eq 1 ] && pass 'All mandatory containers use restart: on-failure' || fail 'At least one restart policy is unexpected'

  header 'Main service processes as PID 1'
  capture_sh 'read /proc/1/cmdline in every container' '
    for c in mariadb wordpress nginx; do
      printf "%s: " "$c"
      docker exec "$c" sh -c '\''tr "\000" " " </proc/1/cmdline; echo'\''
    done'
  expected 'MariaDB PID 1 contains mariadbd
WordPress PID 1 contains php-fpm
NGINX PID 1 contains nginx -g daemon off;'
  local m w n
  m="$(docker exec mariadb sh -c 'tr "\000" " " </proc/1/cmdline' 2>/dev/null || true)"
  w="$(docker exec wordpress sh -c 'tr "\000" " " </proc/1/cmdline' 2>/dev/null || true)"
  n="$(docker exec nginx sh -c 'tr "\000" " " </proc/1/cmdline' 2>/dev/null || true)"
  if [[ "$m" == *mariadbd* && "$w" == *php-fpm* && "$n" == *nginx* && "$n" == *'daemon off;'* ]]; then
    pass 'The real service process is PID 1 in every container'
  else
    fail 'One or more containers has an unexpected PID 1 process'
  fi

  header 'NGINX and PHP-FPM configuration'
  capture_sh 'nginx -t and php-fpm8.2 -t' 'docker exec nginx nginx -t; docker exec wordpress php-fpm8.2 -t'
  expected 'Both configuration tests report success'
  [ "$RC" -eq 0 ] && pass 'NGINX and PHP-FPM configurations are valid' || fail 'NGINX or PHP-FPM configuration validation failed'

  header 'HTTPS home page'
  capture "curl -k https://$(domain)/" curl -k -sS -o /dev/null -w 'status=%{http_code} remote_ip=%{remote_ip} http_version=%{http_version}' "https://$(domain)/"
  expected 'HTTP status 200 through HTTPS'
  [ "$RC" -eq 0 ] && [[ "$OUT" == status=200* ]] && pass 'The WordPress home page is available through HTTPS' || fail 'The HTTPS home page did not return status 200'

  header 'WordPress administrator endpoint'
  capture "curl -k https://$(domain)/wp-admin/" curl -k -sS -o /dev/null -w 'status=%{http_code} redirect=%{redirect_url}' "https://$(domain)/wp-admin/"
  expected 'Unauthenticated /wp-admin/ redirects to wp-login.php'
  [ "$RC" -eq 0 ] && [[ "$OUT" == status=30[12378]* && "$OUT" == *wp-login.php* ]] && pass 'WordPress administrator endpoint redirects to login' || fail 'WordPress administrator endpoint has unexpected behavior'

  header 'HTTP port 80'
  capture "curl http://$(domain)/ with a 3-second timeout" curl -4 -sS --connect-timeout 3 -o /dev/null "http://$(domain)/"
  expected 'Connection fails because port 80 is not published'
  [ "$RC" -ne 0 ] && pass 'Port 80 is closed' || fail 'Port 80 accepts connections'

  header 'Published host ports'
  capture_sh 'inspect PortBindings and host sockets' '
    for c in mariadb wordpress nginx; do docker inspect --format "{{.Name}} PortBindings={{json .HostConfig.PortBindings}}" "$c"; done
    echo; echo Host sockets:; sudo ss -ltnp | grep -E ":(443|3306|9000)\\b" || true'
  expected 'MariaDB and WordPress publish no host ports; NGINX publishes only 443'
  local mp wp np
  mp="$(docker inspect --format '{{json .HostConfig.PortBindings}}' mariadb 2>/dev/null || true)"
  wp="$(docker inspect --format '{{json .HostConfig.PortBindings}}' wordpress 2>/dev/null || true)"
  np="$(docker inspect --format '{{json .HostConfig.PortBindings}}' nginx 2>/dev/null || true)"
  if [ "$mp" = '{}' ] && [ "$wp" = '{}' ] && [[ "$np" == *'"443/tcp"'* && "$np" != *'"80/tcp"'* && "$np" != *'"3306/tcp"'* && "$np" != *'"9000/tcp"'* ]]; then
    pass 'Only NGINX port 443 is published on the host'
  else
    fail 'Published ports differ from the mandatory architecture'
  fi
}

run_tls() {
  require_stack || return

  header 'TLS certificate files'
  capture_sh 'stat and inspect generated TLS files' '
    stat -c "%a %U:%G %n" certificates/inception.crt certificates/inception.key
    openssl x509 -in certificates/inception.crt -noout -subject -issuer -dates -ext subjectAltName'
  expected "Certificate mode 644
Private key mode 600
CN and SAN contain $(domain)"
  local cm km cert
  cm="$(stat -c '%a' "$CERTIFICATE_FILE" 2>/dev/null || true)"
  km="$(stat -c '%a' "$PRIVATE_KEY_FILE" 2>/dev/null || true)"
  cert="$(openssl x509 -in "$CERTIFICATE_FILE" -noout -subject -ext subjectAltName 2>/dev/null || true)"
  if [ -s "$CERTIFICATE_FILE" ] && [ -s "$PRIVATE_KEY_FILE" ] && [ "$cm" = 644 ] && [ "$km" = 600 ] && [[ "$cert" == *"$(domain)"* ]]; then
    pass 'TLS certificate and private key are present and correctly configured'
  else
    fail 'TLS certificate files or metadata are invalid'
  fi

  header 'Certificate hostname'
  capture "openssl x509 -checkhost $(domain)" openssl x509 -in "$CERTIFICATE_FILE" -noout -checkhost "$(domain)"
  expected "Certificate matches hostname $(domain)"
  [ "$RC" -eq 0 ] && pass 'Certificate matches the configured domain' || fail 'Certificate does not match the configured domain'

  header 'Certificate and private-key pair'
  command_text 'extract public keys from certificate and private key, then diff them'
  openssl x509 -in "$CERTIFICATE_FILE" -pubkey -noout >"$TMP_DIR/cert.pub" 2>"$TMP_DIR/cert.err"; local a=$?
  openssl pkey -in "$PRIVATE_KEY_FILE" -pubout >"$TMP_DIR/key.pub" 2>"$TMP_DIR/key.err"; local b=$?
  local d; d="$(diff "$TMP_DIR/cert.pub" "$TMP_DIR/key.pub" 2>&1)"; local c=$?
  evidence "certificate extraction exit=$a
private-key extraction exit=$b
public-key diff exit=$c
${d:-public keys are identical}"
  expected 'Both public keys are identical'
  [ "$a" -eq 0 ] && [ "$b" -eq 0 ] && [ "$c" -eq 0 ] && pass 'Certificate and private key form a matching pair' || fail 'Certificate and private key do not match'

  tls_accept TLSv1.2 tls1_2
  tls_accept TLSv1.3 tls1_3
  tls_reject 'TLS 1.0' tls1
  tls_reject 'TLS 1.1' tls1_1
}

tls_accept() {
  local label="$1" flag="$2"
  header "$label support"
  capture_sh "openssl s_client -$flag to $(domain):443" "openssl s_client -brief -connect '$(domain):443' -servername '$(domain)' -$flag </dev/null 2>&1 | grep -E 'Protocol version|Ciphersuite|Verification error'"
  expected "Protocol version: $label"
  [ "$RC" -eq 0 ] && [[ "$OUT" == *"Protocol version: $label"* ]] && pass "$label is accepted" || fail "$label is not accepted"
}

tls_reject() {
  local label="$1" flag="$2"
  header "$label rejection"
  capture_sh "openssl s_client -$flag to $(domain):443" "openssl s_client -brief -connect '$(domain):443' -servername '$(domain)' -$flag -cipher 'ALL:@SECLEVEL=0' </dev/null 2>&1"
  expected "$label handshake fails with a protocol-version alert"
  [ "$RC" -ne 0 ] && [[ "$OUT" == *'protocol version'* || "$OUT" == *'alert number 70'* ]] && pass "$label is rejected" || fail "$label was accepted or rejected unexpectedly"
}

run_wordpress() {
  require_stack || return

  header 'WordPress installation'
  capture_sh 'check WordPress installation and version' '
    docker exec -u www-data wordpress wp --path=/var/www/html core is-installed
    printf "version="
    docker exec -u www-data wordpress wp --path=/var/www/html core version'
  expected 'WP-CLI confirms that WordPress is installed and prints a version'
  [ "$RC" -eq 0 ] && [[ "$OUT" == *version=* ]] && pass 'WordPress is installed' || fail 'WordPress installation check failed'

  header 'WordPress site options'
  capture_sh 'read siteurl, home, and blogname' '
    printf "siteurl="; docker exec -u www-data wordpress wp --path=/var/www/html option get siteurl
    printf "home="; docker exec -u www-data wordpress wp --path=/var/www/html option get home
    printf "blogname="; docker exec -u www-data wordpress wp --path=/var/www/html option get blogname'
  expected "siteurl=https://$(domain)
home=https://$(domain)
blogname=Inception"
  local site home title
  site="$(docker exec -u www-data wordpress wp --path=/var/www/html option get siteurl 2>/dev/null || true)"
  home="$(docker exec -u www-data wordpress wp --path=/var/www/html option get home 2>/dev/null || true)"
  title="$(docker exec -u www-data wordpress wp --path=/var/www/html option get blogname 2>/dev/null || true)"
  [ "$site" = "https://$(domain)" ] && [ "$home" = "https://$(domain)" ] && [ "$title" = Inception ] && pass 'WordPress site options are correct' || fail 'WordPress site options are unexpected'

  header 'WordPress database configuration'
  capture_sh 'read non-secret DB settings through WP-CLI' '
    for k in DB_NAME DB_USER DB_HOST; do
      printf "%s=" "$k"
      docker exec -u www-data wordpress wp --path=/var/www/html config get "$k"
    done'
  expected "DB_NAME=$(db_name)
DB_USER=$(db_user)
DB_HOST=mariadb:3306"
  [[ "$OUT" == *"DB_NAME=$(db_name)"* && "$OUT" == *"DB_USER=$(db_user)"* && "$OUT" == *'DB_HOST=mariadb:3306'* ]] && pass 'WordPress uses the expected MariaDB connection settings' || fail 'WordPress database configuration is unexpected'

  header 'WordPress users and roles'
  capture 'wp user list --fields=ID,user_login,user_email,roles' docker exec -u www-data wordpress wp --path=/var/www/html user list --fields=ID,user_login,user_email,roles --format=table
  expected "$(wp_admin) has role administrator
$(wp_user) exists with a non-administrator role
Administrator username does not contain admin"
  local csv admin second
  admin="$(wp_admin)"; second="$(wp_user)"
  csv="$(docker exec -u www-data wordpress wp --path=/var/www/html user list --fields=user_login,roles --format=csv 2>/dev/null || true)"
  if [[ "$admin" =~ [Aa][Dd][Mm][Ii][Nn] ]]; then
    fail 'Administrator username contains the forbidden substring admin'
  elif echo "$csv" | grep -Eq "^${admin},administrator$" && echo "$csv" | grep -Eq "^${second},(author|editor|contributor|subscriber)$"; then
    pass 'Required WordPress users and roles are configured correctly'
  else
    fail 'Required WordPress users or roles are missing'
  fi
}

run_mariadb() {
  require_stack || return

  header 'MariaDB databases and accounts'
  capture_sh 'query databases and mysql.user through the root socket account' 'docker exec mariadb sh -c '\''
    MYSQL_PWD="$(cat /run/secrets/db_root_password)" \
    mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock --user=root --execute="
      SHOW DATABASES;
      SELECT User, Host FROM mysql.user ORDER BY User, Host;
    "
  '\'''
  expected "Database $(db_name) exists
Application account $(db_user)@% exists
Root account exists for localhost"
  if [ "$RC" -eq 0 ] && echo "$OUT" | grep -Fxq "$(db_name)" && echo "$OUT" | grep -Eq "^$(db_user)[[:space:]]+%$" && echo "$OUT" | grep -Eq '^root[[:space:]]+localhost$'; then
    pass 'MariaDB database and accounts are configured'
  else
    fail 'MariaDB database or required accounts are missing'
  fi

  header 'MariaDB application connection'
  capture_sh 'connect as the WordPress database user through TCP' 'docker exec mariadb sh -c '\''
    MYSQL_PWD="$(cat /run/secrets/db_password)" \
    mariadb --protocol=tcp --host=127.0.0.1 --port="$MARIADB_PORT" --user="$MYSQL_USER" --database="$MYSQL_DATABASE" --execute="
      SELECT DATABASE() AS current_database;
      SELECT COUNT(*) AS wordpress_tables FROM information_schema.tables WHERE table_schema = DATABASE();
    "
  '\'''
  expected "current_database=$(db_name)
WordPress table count is greater than zero"
  local count
  count="$(echo "$OUT" | awk '/^[0-9]+$/ {v=$1} END {print v}')"
  if [ "$RC" -eq 0 ] && echo "$OUT" | grep -Fxq "$(db_name)" && [[ "$count" =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ]; then
    pass 'WordPress database user can access initialized tables'
  else
    fail 'WordPress database user cannot access valid WordPress tables'
  fi

  header 'MariaDB application privileges'
  capture "SHOW GRANTS FOR application user" \
    docker exec mariadb sh -c \
      'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock --user=root --execute="SHOW GRANTS FOR '\''$MYSQL_USER'\''@'\''%'\'';"'
  expected "$(db_user) has privileges on $(db_name).*"
  [ "$RC" -eq 0 ] && [[ "$OUT" == *"$(db_name)"* && "$OUT" == *"$(db_user)"* ]] && pass 'Application account has privileges on the WordPress database' || fail 'Application account privileges are missing or unexpected'

  header 'MariaDB runtime configuration'
  capture_sh 'query bind_address and port' 'docker exec mariadb sh -c '\''
    MYSQL_PWD="$(cat /run/secrets/db_root_password)" \
    mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock --user=root --execute="
      SHOW VARIABLES LIKE '\''\''bind_address'\''\'';
      SHOW VARIABLES LIKE '\''\''port'\''\'';
    "
  '\'''
  expected 'bind_address=0.0.0.0
port=3306'
  [ "$RC" -eq 0 ] && echo "$OUT" | grep -Eq 'bind_address[[:space:]]+0\.0\.0\.0' && echo "$OUT" | grep -Eq 'port[[:space:]]+3306' && pass 'MariaDB listens on the expected internal address and port' || fail 'MariaDB bind address or port is unexpected'

  header 'MariaDB initialization state'
  capture 'list system tables, project marker, and WordPress database directory' docker exec mariadb sh -c 'ls -ld /var/lib/mysql/mysql /var/lib/mysql/.inception_initialized /var/lib/mysql/wordpress'
  expected 'System tables, initialization marker, and WordPress database directory exist'
  [ "$RC" -eq 0 ] && pass 'MariaDB persistent initialization state is complete' || fail 'MariaDB initialization files are incomplete'
}

run_network() {
  require_stack || return

  header 'Docker network membership'
  capture_sh 'inspect inception_inception' 'docker network inspect inception_inception --format "driver={{.Driver}}
{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{println}}{{end}}"'
  expected 'Bridge driver with mariadb, nginx, and wordpress attached'
  local driver members
  driver="$(docker network inspect inception_inception --format '{{.Driver}}' 2>/dev/null || true)"
  members="$(docker network inspect inception_inception --format '{{range .Containers}}{{println .Name}}{{end}}' 2>/dev/null | sort || true)"
  [ "$driver" = bridge ] && [ "$members" = $'mariadb\nnginx\nwordpress' ] && pass 'All mandatory containers share the project bridge network' || fail 'Docker network membership or driver is unexpected'

  header 'Docker DNS'
  capture_sh 'resolve mariadb from WordPress and wordpress from NGINX' 'docker exec wordpress getent hosts mariadb; docker exec nginx getent hosts wordpress'
  expected 'WordPress resolves mariadb
NGINX resolves wordpress'
  [ "$RC" -eq 0 ] && echo "$OUT" | grep -Eq '[[:space:]]mariadb$' && echo "$OUT" | grep -Eq '[[:space:]]wordpress$' && pass 'Docker DNS resolves internal service names' || fail 'Docker DNS resolution failed'

  header 'Internal service connectivity'
  capture_sh 'query MariaDB from WordPress and the website through NGINX' 'docker exec wordpress sh -c '\''
    MYSQL_PWD="$(cat /run/secrets/db_password)" \
    mariadb --protocol=tcp --host="$MYSQL_HOST" --port="$MARIADB_PORT" --user="$MYSQL_USER" --database="$MYSQL_DATABASE" --execute="SELECT 1 AS database_path;"
  '\''
  d="$(sed -n "s/^DOMAIN_NAME=//p" srcs/.env | tail -n 1)"
  curl -k -sS -o /dev/null -w "nginx_wordpress_path=%{http_code}\n" "https://$d/"'
  expected 'WordPress reaches mariadb:3306
NGINX reaches WordPress and returns HTTP 200'
  [ "$RC" -eq 0 ] && echo "$OUT" | grep -Fxq 1 && echo "$OUT" | grep -Fxq 'nginx_wordpress_path=200' && pass 'The complete internal request path is operational' || fail 'Internal service connectivity is broken'

  header 'Shared WordPress volume'
  capture_sh 'inspect WordPress and NGINX mounts' '
    for c in wordpress nginx; do
      echo "$c mounts:"
      docker inspect "$c" --format "{{range .Mounts}}{{println .Name \"->\" .Destination \"RW=\" .RW \"Source=\" .Source}}{{end}}"
    done'
  expected 'WordPress and NGINX use the same /var/www/html source
NGINX mount is read-only'
  local ws ns nrw
  ws="$(docker inspect wordpress --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"
  ns="$(docker inspect nginx --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)"
  nrw="$(docker inspect nginx --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.RW}}{{end}}{{end}}' 2>/dev/null || true)"
  [ -n "$ws" ] && [ "$ws" = "$ns" ] && [ "$nrw" = false ] && pass 'WordPress files are shared with NGINX through a read-only mount' || fail 'WordPress shared-volume mounts are unexpected'
}

run_persistence() {
  require_stack || return

  header 'Create persistence evidence'
  PERSIST_ID="persistence-$(date '+%Y%m%d-%H%M%S')"
  command_text 'create a WordPress volume file and a draft database record'
  docker exec -u www-data wordpress sh -c "printf '%s\n' '$PERSIST_ID' > '/var/www/html/wp-content/${PERSIST_ID}.txt'" >"$TMP_DIR/file-create.log" 2>&1; local fe=$?
  POST_ID="$(docker exec -u www-data wordpress wp --path=/var/www/html post create --post_type=post --post_status=draft --post_title="$PERSIST_ID" --porcelain 2>"$TMP_DIR/post-create.log")"; local pe=$?
  local cv hv post_ev
  cv="$(docker exec wordpress cat "/var/www/html/wp-content/${PERSIST_ID}.txt" 2>/dev/null || true)"
  hv="$(sudo cat "$WORDPRESS_DATA_DIR/wp-content/${PERSIST_ID}.txt" 2>/dev/null || true)"
  post_ev="$(docker exec -u www-data wordpress wp --path=/var/www/html post get "$POST_ID" --fields=ID,post_title,post_status --format=table 2>/dev/null || true)"
  evidence "test_id=$PERSIST_ID
post_id=$POST_ID
container_file=$cv
host_file=$hv
$post_ev
$(cat "$TMP_DIR/file-create.log" "$TMP_DIR/post-create.log" 2>/dev/null || true)"
  expected 'The same unique value exists in the container, host volume, and draft post'
  if [ "$fe" -eq 0 ] && [ "$pe" -eq 0 ] && [ -n "$POST_ID" ] && [ "$cv" = "$PERSIST_ID" ] && [ "$hv" = "$PERSIST_ID" ] && [[ "$post_ev" == *"$PERSIST_ID"* && "$post_ev" == *draft* ]]; then
    pass 'Persistence test data was created in both volumes'
  else
    fail 'Could not create valid persistence test data'
    return
  fi

  header 'Named volume configuration'
  capture_sh 'inspect mariadb_data and wordpress_data' '
    docker volume inspect mariadb_data --format "name={{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}} options={{json .Options}}"
    docker volume inspect wordpress_data --format "name={{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}} options={{json .Options}}"'
  expected "mariadb_data uses $MARIADB_DATA_DIR
wordpress_data uses $WORDPRESS_DATA_DIR"
  [ "$RC" -eq 0 ] && [[ "$OUT" == *"$MARIADB_DATA_DIR"* && "$OUT" == *"$WORDPRESS_DATA_DIR"* ]] && pass 'Named volumes use the expected host directories' || fail 'Named volume backing directories are unexpected'

  header 'Remove containers without deleting persistent data'
  capture 'make down' make down
  local down_out="$OUT" down_rc="$RC"
  local containers volumes host_after db_after
  containers="$(compose ps -a 2>&1 || true)"
  volumes="$(docker volume ls --format '{{.Name}}' | grep -E '^(mariadb_data|wordpress_data)$' | sort || true)"
  host_after="$(sudo cat "$WORDPRESS_DATA_DIR/wp-content/${PERSIST_ID}.txt" 2>/dev/null || true)"
  db_after="$(sudo test -d "$MARIADB_DATA_DIR/wordpress" && echo present || echo missing)"
  evidence "$down_out

Containers after make down:
$containers

Volumes after make down:
$volumes

Host WordPress file:
$host_after

MariaDB database directory:
$db_after"
  expected 'Containers are removed
Both named volumes remain
WordPress test file remains
MariaDB database directory remains'
  if [ "$down_rc" -eq 0 ] && [ -z "$(compose ps -aq 2>/dev/null || true)" ] && [ "$volumes" = $'mariadb_data\nwordpress_data' ] && [ "$host_after" = "$PERSIST_ID" ] && [ "$db_after" = present ]; then
    pass 'Persistent data survived container removal'
  else
    fail 'Persistent data or named volumes were lost after make down'
  fi

  header 'Recreate containers with preserved volumes'
  capture 'make' make
  local make_out="$OUT" make_rc="$RC"
  wait_stack 120; local stack_rc=$RC stack_out="$OUT"
  wait_https 90; local https_rc=$RC https_out="$OUT"
  evidence "$make_out

Stack readiness:
$stack_out

Endpoint readiness:
$https_out"
  expected 'make succeeds, all containers run, and HTTPS returns 200'
  if [ "$make_rc" -eq 0 ] && [ "$stack_rc" -eq 0 ] && [ "$https_rc" -eq 0 ]; then
    pass 'Containers were recreated successfully with preserved volumes'
  else
    fail 'Container recreation or service readiness failed'
    return
  fi

  header 'Verify preserved WordPress and MariaDB data'
  cv="$(docker exec wordpress cat "/var/www/html/wp-content/${PERSIST_ID}.txt" 2>/dev/null || true)"
  hv="$(sudo cat "$WORDPRESS_DATA_DIR/wp-content/${PERSIST_ID}.txt" 2>/dev/null || true)"
  post_ev="$(docker exec -u www-data wordpress wp --path=/var/www/html post get "$POST_ID" --fields=ID,post_title,post_status --format=table 2>/dev/null || true)"
  local users
  users="$(docker exec -u www-data wordpress wp --path=/var/www/html user list --fields=ID,user_login,roles --format=table 2>/dev/null || true)"
  command_text 'read the original file and draft after container recreation'
  evidence "expected=$PERSIST_ID
container_file=$cv
host_file=$hv

Database draft:
$post_ev

WordPress users:
$users"
  expected 'The original unique file value and draft record are unchanged'
  if [ "$cv" = "$PERSIST_ID" ] && [ "$hv" = "$PERSIST_ID" ] && [[ "$post_ev" == *"$PERSIST_ID"* && "$post_ev" == *draft* ]]; then
    pass 'WordPress files and MariaDB records survived container recreation'
  else
    fail 'WordPress or MariaDB persistence verification failed'
  fi

  header 'Initialization idempotency'
  local ml wl markers
  ml="$(compose logs --no-color mariadb 2>&1 || true)"
  wl="$(compose logs --no-color wordpress 2>&1 || true)"
  markers="$(printf '%s\n' "$ml" | grep -E 'Initializing MariaDB|Configuring the Inception|initialization completed' || true)"
  command_text 'inspect MariaDB and WordPress logs after preserved-volume startup'
  evidence "MariaDB initialization markers:
${markers:-<none>}

WordPress startup:
$wl"
  expected 'MariaDB full initialization is absent
WordPress reports existing files, installation, and second user'
  if [ -z "$markers" ] && [[ "$wl" == *'WordPress files already exist.'* && "$wl" == *'WordPress is already installed.'* && "$wl" == *'Second WordPress user already exists.'* ]]; then
    pass 'Preserved data prevents repeated initialization'
  else
    fail 'MariaDB or WordPress initialization was unexpectedly repeated'
  fi

  header 'Remove persistence test data'
  command_text 'delete the temporary draft and volume file'
  local del_post del_file file_exists=0 post_exists=0
  del_post="$(docker exec -u www-data wordpress wp --path=/var/www/html post delete "$POST_ID" --force 2>&1)"; local dpe=$?
  del_file="$(docker exec -u www-data wordpress rm -f "/var/www/html/wp-content/${PERSIST_ID}.txt" 2>&1)"; local dfe=$?
  docker exec wordpress test -e "/var/www/html/wp-content/${PERSIST_ID}.txt" >/dev/null 2>&1 && file_exists=1
  docker exec -u www-data wordpress wp --path=/var/www/html post get "$POST_ID" >/dev/null 2>&1 && post_exists=1
  evidence "draft deletion exit=$dpe
$del_post
file deletion exit=$dfe
$del_file
file_exists_after_cleanup=$file_exists
post_exists_after_cleanup=$post_exists"
  expected 'Temporary draft and volume file are both removed'
  if [ "$dpe" -eq 0 ] && [ "$dfe" -eq 0 ] && [ "$file_exists" -eq 0 ] && [ "$post_exists" -eq 0 ]; then
    PERSIST_ID=""; POST_ID=""; pass 'Persistence test data was removed'
  else
    fail 'Persistence test cleanup was incomplete'
  fi
}

crash_one() {
  local c="$1" kind="$2"
  header "$c automatic crash restart"
  local before pid state after attempt=0 transitions="" service_out="" service_rc=1
  before="$(docker inspect --format '{{.RestartCount}}' "$c" 2>/dev/null || echo 0)"
  pid="$(docker inspect --format '{{.State.Pid}}' "$c" 2>/dev/null || echo 0)"
  command_text "sudo kill -KILL host PID $pid for $c"
  sudo kill -KILL "$pid" >"$TMP_DIR/$c-kill.log" 2>&1; local ke=$?
  state=unknown; after="$before"
  while [ "$attempt" -lt 30 ]; do
    state="$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo missing)"
    after="$(docker inspect --format '{{.RestartCount}}' "$c" 2>/dev/null || echo 0)"
    transitions+="attempt $attempt: state=$state restart_count=$after"$'\n'
    [ "$state" = running ] && [ "$after" -gt "$before" ] && break
    attempt=$((attempt + 1)); sleep 1
  done
  case "$kind" in
    https)
      sleep 2
      service_out="$(curl -k -sS -o /dev/null -w 'HTTPS status=%{http_code}' "https://$(domain)/" 2>&1)"; service_rc=$?
      [[ "$service_out" == *'status=200'* ]] || service_rc=1
      ;;
    wordpress)
      sleep 3
      service_out="$(docker exec -u www-data wordpress wp --path=/var/www/html core is-installed 2>&1)"; service_rc=$?
      [ "$service_rc" -eq 0 ] && service_out="${service_out}${service_out:+$'\n'}WordPress core is installed"
      ;;
    mariadb)
      sleep 8
      service_out="$(docker exec mariadb sh -c '
        MYSQL_PWD="$(cat /run/secrets/db_password)" \
        mariadb --protocol=tcp --host=127.0.0.1 --port="$MARIADB_PORT" --user="$MYSQL_USER" --database="$MYSQL_DATABASE" --execute="SELECT 1 AS database_available;"
      ' 2>&1)"; service_rc=$?
      ;;
  esac
  evidence "host_pid=$pid
restart_count_before=$before
kill_exit=$ke
$(cat "$TMP_DIR/$c-kill.log" 2>/dev/null || true)

Observed transitions:
${transitions%$'\n'}

Final state:
state=$state
restart_count_after=$after

Service verification:
$service_out"
  expected 'Host PID is killed unexpectedly
RestartCount increases
Container returns to running
Service-specific verification succeeds'
  if [ "$ke" -eq 0 ] && [ "$state" = running ] && [ "$after" -gt "$before" ] && [ "$service_rc" -eq 0 ]; then
    pass "$c restarted automatically and recovered its service"
  else
    fail "$c did not recover correctly after its main process crashed"
  fi
}

run_restart() {
  require_stack || return
  header 'Privilege check for crash simulation'
  capture 'sudo -v' sudo -v
  expected 'sudo authentication succeeds'
  if [ "$RC" -eq 0 ]; then pass 'Required privileges are available for crash simulation'; else fail 'sudo privileges are unavailable'; return; fi
  printf '\nWaiting 10 seconds so restart policies are fully active...\n'; sleep 10
  crash_one nginx https
  crash_one wordpress wordpress
  crash_one mariadb mariadb

  header 'Website after all crash tests'
  wait_https 60
  command_text "curl -k https://$(domain)/"; evidence "$OUT"; expected 'Final HTTPS status is 200'
  [ "$RC" -eq 0 ] && pass 'Website works after all service crash recoveries' || fail 'Website did not recover after the crash sequence'
}

run_security() {
  header 'Git working tree'
  capture_sh 'show branch, status, and latest commit' '
    printf "branch="; git branch --show-current
    echo status:; git status --short
    echo latest_commit:; git log -1 --oneline'
  expected 'Branch main and no output from git status --short'
  local gs
  gs="$(git status --short 2>/dev/null || true)"
  [ "$(git branch --show-current 2>/dev/null || true)" = main ] && [ -z "$gs" ] && pass 'Git working tree is clean on main' || fail 'Git working tree is not clean on main'

  header 'Tracked secret and certificate paths'
  capture 'git ls-files secrets certificates' git ls-files secrets certificates
  expected 'Only certificates/.gitkeep and secrets/.gitkeep are tracked'
  local tracked
  tracked="$(printf '%s\n' "$OUT" | sort)"
  [ "$tracked" = $'certificates/.gitkeep\nsecrets/.gitkeep' ] && pass 'No generated secret or TLS payload is tracked' || fail 'Unexpected files under secrets or certificates are tracked'

  header 'Git ignore rules for secrets and certificates'
  capture 'git check-ignore -v required generated files' git check-ignore -v \
    secrets/db_root_password.txt secrets/db_password.txt secrets/wp_admin_password.txt secrets/wp_user_password.txt \
    certificates/inception.crt certificates/inception.key
  expected 'All six generated files match .gitignore rules'
  [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | sed '/^$/d' | wc -l)" -eq 6 ] && pass 'Secrets and generated TLS files are ignored by Git' || fail 'One or more sensitive files is not ignored'

  header 'Sensitive paths in Git history'
  capture_sh 'search all Git objects and history for sensitive paths' '
    git rev-list --objects --all | grep -E "(^| )(secrets/.*\.txt|certificates/.*\.key|credentials\.txt)$" || true
    git log --all --format= --name-only -- \
      secrets/db_root_password.txt secrets/db_password.txt secrets/wp_admin_password.txt secrets/wp_user_password.txt certificates/inception.key \
      | sed "/^$/d" | sort -u'
  expected 'No output'
  [ -z "$OUT" ] && pass 'No secret file or private-key path exists in Git history' || fail 'A sensitive path exists in Git history'

  header 'Current secret values in tracked files'
  local ev="" f value valid=1
  for f in "${SECRET_FILES[@]}"; do
    value="$(tr -d '\r\n' <"$f" 2>/dev/null || true)"
    if [ -z "$value" ]; then ev+="${f#"$PROJECT_ROOT/"}: empty"$'\n'; valid=0
    elif git grep -F -q -e "$value" --; then ev+="${f#"$PROJECT_ROOT/"}: value found in tracked files"$'\n'; valid=0
    else ev+="${f#"$PROJECT_ROOT/"}: value absent from tracked files"$'\n'; fi
  done
  command_text 'compare each secret value against tracked files without printing it'; evidence "${ev%$'\n'}"
  expected 'Every secret value is absent from tracked files'; note 'Actual secret values are never printed'
  [ "$valid" -eq 1 ] && pass 'Current secret values are absent from tracked files' || fail 'A secret is empty or appears in a tracked file'

  if stack_running; then
    header 'Password values in container environments'
    ev=""; valid=1
    local c found
    for c in "${CONTAINERS[@]}"; do
      found="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null | grep -Ei '(PASSWORD|PASSWD|SECRET)=' || true)"
      if [ -n "$found" ]; then ev+="$c:"$'\n'"$found"$'\n'; valid=0; else ev+="$c: no password values in environment"$'\n'; fi
    done
    command_text 'inspect container environments for password-like keys'; evidence "${ev%$'\n'}"
    expected 'No password or secret value is passed through environment variables'
    [ "$valid" -eq 1 ] && pass 'Container environments do not contain password values' || fail 'A password-like value is present in a container environment'
  else
    header 'Password values in container environments'; skip 'Container environment audit requires a running stack'
  fi

  header 'Forbidden container runtime patterns'
  capture_sh 'grep Docker sources for forbidden runtime hacks' 'grep -RInE "tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+(true|:)|network_mode:[[:space:]]*host|^[[:space:]]*links:" srcs || true'
  expected 'No output'
  [ -z "$OUT" ] && pass 'No forbidden container runtime hack was found' || fail 'A forbidden container runtime pattern was found'

  header 'Latest image tags'
  capture_sh 'search Docker sources for :latest' 'grep -RInE "FROM[[:space:]]+[^[:space:]]*:latest|image:[[:space:]]*[^[:space:]]*:latest" srcs || true'
  expected 'No output'
  [ -z "$OUT" ] && pass 'No latest image tag is used' || fail 'A latest image tag is used'

  header 'Dockerfile base images'
  capture_sh 'find every Dockerfile and print FROM instructions' 'find srcs/requirements -name Dockerfile -exec grep -H "^FROM " {} +'
  expected 'Exactly three Dockerfiles, each using FROM debian:bookworm'
  local lines count
  lines="$(printf '%s\n' "$OUT" | sed '/^$/d')"; count="$(printf '%s\n' "$lines" | wc -l)"
  if [ "$RC" -eq 0 ] && [ "$count" -eq 3 ] && ! printf '%s\n' "$lines" | grep -v 'FROM debian:bookworm' >/dev/null; then
    pass 'All custom images use the expected Debian base'
  else
    fail 'Dockerfile base images are unexpected'
  fi

  test_compose_architecture
}

cold_logs() {
  header 'Cold-start service logs'
  local ml wl nl
  ml="$(compose logs --no-color mariadb 2>&1 || true)"
  wl="$(compose logs --no-color wordpress 2>&1 || true)"
  nl="$(compose logs --no-color nginx 2>&1 || true)"
  command_text 'docker compose logs for mariadb, wordpress, and nginx'
  evidence "===== MariaDB =====
$ml

===== WordPress =====
$wl

===== NGINX =====
$nl"
  expected 'MariaDB initializes and becomes ready
WordPress installs and creates the second user
NGINX configuration test succeeds'
  if [[ "$ml" == *'ready for connections'* && "$wl" == *'WordPress installed.'* && "$wl" == *'Second WordPress user created.'* && "$nl" == *'test is successful'* ]]; then
    pass 'Cold-start logs confirm successful initialization of all services'
  else
    fail 'Cold-start logs do not contain all expected initialization evidence'
  fi
}

cold_domain() {
  header 'Local domain resolution'
  capture_sh "getent hosts and inspect /etc/hosts for $(domain)" "getent hosts '$(domain)'; grep -n '$(domain)' /etc/hosts"
  expected "$(domain) resolves to 127.0.0.1"
  [ "$RC" -eq 0 ] && echo "$OUT" | grep -Eq "127\.0\.0\.1[[:space:]]+$(domain)" && pass 'Project domain resolves to the local VM' || fail 'Project domain does not resolve to 127.0.0.1'
}

cold_host_data() {
  header 'Persistent host data layout'
  capture_sh 'inspect MariaDB and WordPress host directories' 'sudo find /home/"$(id -un)"/data -maxdepth 2 -printf "%M %u:%g %p\n" | head -n 100'
  expected 'MariaDB system/database directories and WordPress core directories exist'
  if [ "$RC" -eq 0 ] && sudo test -d "$MARIADB_DATA_DIR/mysql" && sudo test -d "$MARIADB_DATA_DIR/wordpress" && sudo test -f "$MARIADB_DATA_DIR/.inception_initialized" \
    && sudo test -d "$WORDPRESS_DATA_DIR/wp-admin" && sudo test -d "$WORDPRESS_DATA_DIR/wp-content" && sudo test -d "$WORDPRESS_DATA_DIR/wp-includes" && sudo test -f "$WORDPRESS_DATA_DIR/wp-config.php"; then
    pass 'Persistent host directories contain initialized MariaDB and WordPress data'
  else
    fail 'Persistent host data layout is incomplete'
  fi
}

run_cold_start() {
  confirm_delete

  header 'Complete project cleanup'
  capture 'make fclean' make fclean
  expected 'Project containers, images, volumes, network, and host data are removed'
  [ "$RC" -eq 0 ] && pass 'make fclean completed successfully' || fail 'make fclean failed'

  header 'Cleanup verification'
  local ev
  ev="containers:
$(compose ps -a 2>&1 || true)

images:
$(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^(mariadb|wordpress|nginx):inception$' || true)

volumes:
$(docker volume ls --format '{{.Name}}' | grep -E '^(mariadb_data|wordpress_data)$' || true)

network:
$(docker network ls --format '{{.Name}}' | grep '^inception_inception$' || true)

host_data:
$(if [ -e "$DATA_DIR" ]; then echo present; else echo removed; fi)"
  command_text 'inspect containers, images, volumes, network, and host data after fclean'; evidence "$ev"
  expected 'No project containers, images, volumes, network, or host data directory'
  if [ -z "$(compose ps -aq 2>/dev/null || true)" ] \
    && [ -z "$(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^(mariadb|wordpress|nginx):inception$' || true)" ] \
    && [ -z "$(docker volume ls --format '{{.Name}}' | grep -E '^(mariadb_data|wordpress_data)$' || true)" ] \
    && [ -z "$(docker network ls --format '{{.Name}}' | grep '^inception_inception$' || true)" ] \
    && [ ! -e "$DATA_DIR" ]; then pass 'Complete cleanup state is correct'; else fail 'Cleanup left infrastructure or data behind'; fi

  header 'Remove generated TLS files'
  command_text 'rm -f certificates/inception.crt certificates/inception.key'
  rm -f "$CERTIFICATE_FILE" "$PRIVATE_KEY_FILE"
  evidence "$(ls -la certificates 2>&1 || true)"
  expected 'Generated certificate and private key are absent'
  [ ! -e "$CERTIFICATE_FILE" ] && [ ! -e "$PRIVATE_KEY_FILE" ] && pass 'Generated TLS files were removed for a true cold start' || fail 'Generated TLS files could not be removed'

  header 'Cold build and startup'
  capture 'make' make
  local mo="$OUT" mr="$RC"
  wait_stack 120; local sr=$RC so="$OUT"
  wait_https 90; local hr=$RC ho="$OUT"
  evidence "$mo

Stack readiness:
$so

Endpoint readiness:
$ho"
  expected 'make succeeds, all containers run, and HTTPS returns 200'
  if [ "$mr" -eq 0 ] && [ "$sr" -eq 0 ] && [ "$hr" -eq 0 ]; then
    pass 'The complete infrastructure started successfully from an empty state'
  else
    fail 'Cold build or startup failed'
  fi

  if stack_running; then cold_logs; cold_domain; cold_host_data; else header 'Cold-start continuation'; skip 'Cold-start validation requires all containers to be running'; fi
}

final_state() {
  header 'Final acceptance state'
  capture_sh 'show final containers, policies, HTTPS, and Git state' '
    docker compose -f srcs/docker-compose.yml ps -a
    echo; echo Container details:
    for c in mariadb wordpress nginx; do docker inspect --format "{{.Name}} state={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} policy={{.HostConfig.RestartPolicy.Name}}" "$c"; done
    d="$(sed -n "s/^DOMAIN_NAME=//p" srcs/.env | tail -n 1)"
    echo; curl -k -sS -o /dev/null -w "FINAL HTTPS status=%{http_code}\n" "https://$d/"
    echo; echo Git status:; git status --short'
  expected 'All containers running with on-failure
HTTPS status 200
Clean Git working tree'
  local code gs
  code="$(curl -k -sS -o /dev/null -w '%{http_code}' "https://$(domain)/" 2>/dev/null || true)"
  gs="$(git status --short 2>/dev/null || true)"
  stack_running && [ "$code" = 200 ] && [ -z "$gs" ] && pass 'Final mandatory acceptance state is healthy' || fail 'Final mandatory acceptance state is not clean and healthy'
}

summary() {
  printf '\n'; line; printf '%bMANDATORY TEST SUMMARY%b\n' "$BOLD" "$RESET"; line; printf '\n'
  local r st name msg
  for r in "${RESULTS[@]}"; do
    IFS='|' read -r st name msg <<<"$r"
    case "$st" in
      PASS) printf '%b[PASS]%b %s — %s\n' "$GREEN" "$RESET" "$name" "$msg" ;;
      FAIL) printf '%b[FAIL]%b %s — %s\n' "$RED" "$RESET" "$name" "$msg" ;;
      SKIP) printf '%b[SKIP]%b %s — %s\n' "$YELLOW" "$RESET" "$name" "$msg" ;;
    esac
  done
  printf '\nPassed:  %d\nFailed:  %d\nSkipped: %d\n\n' "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  if [ "$FAIL_COUNT" -eq 0 ]; then printf '%bRESULT: PASS%b\n' "$GREEN$BOLD" "$RESET"; else printf '%bRESULT: FAIL%b\n' "$RED$BOLD" "$RESET"; fi
  printf 'Full evidence log:\n  %s\n' "$LOG_FILE"
}

case "$MODE" in
  preflight) run_preflight ;;
  runtime) run_runtime ;;
  tls) run_tls ;;
  wordpress) run_wordpress ;;
  mariadb) run_mariadb ;;
  network) run_network ;;
  persistence) run_persistence ;;
  restart) run_restart ;;
  security) run_security ;;
  cold-start)
    run_preflight
    if [ "$FAIL_COUNT" -eq 0 ]; then
      run_cold_start
      if stack_running; then run_runtime; run_tls; run_wordpress; run_mariadb; run_network; fi
      final_state
    else
      header 'Destructive cold-start continuation'
      skip 'Cold-start was not executed because preflight checks failed'
    fi
    ;;
  full)
    run_preflight
    if [ "$FAIL_COUNT" -eq 0 ]; then
      run_cold_start
      if stack_running; then
        run_runtime
        run_tls
        run_wordpress
        run_mariadb
        run_network
        run_persistence
        run_restart
      else
        header 'Full-suite runtime continuation'; skip 'Runtime tests were skipped because the cold-start stack is not running'
      fi
      run_security
      final_state
    else
      header 'Destructive full-suite continuation'
      skip 'The destructive suite was not executed because preflight checks failed'
      run_security
    fi
    ;;
esac

summary
[ "$FAIL_COUNT" -eq 0 ] && exit 0 || exit 1

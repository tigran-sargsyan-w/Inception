#!/usr/bin/env bash

# ==============================================================================
# Inception Mandatory Test Runner
# ==============================================================================
#
# This script automates the technical validation of the mandatory part of the
# Inception project. Each test prints the executed command, its real output as
# evidence, the expected result, and a final [PASS], [FAIL], or [SKIP] status.
#
# Available modes:
#
#   list
#       Shows all available test modes with a short description.
#
#   preflight
#       Checks required tools, the Docker daemon, environment files, local
#       secrets, file permissions, and the resolved Docker Compose structure.
#
#   runtime
#       Checks that all containers are running, verifies their PID 1 processes
#       and restart policies, validates NGINX and PHP-FPM, and tests HTTPS and
#       published ports.
#
#   tls
#       Checks the generated certificate and private key, verifies the domain
#       name and matching key pair, accepts TLS 1.2/1.3, and rejects TLS 1.0/1.1.
#
#   wordpress
#       Verifies that WordPress is installed, checks its URL, title, database
#       configuration, administrator account, second user, and assigned roles.
#
#   mariadb
#       Verifies the WordPress database, MariaDB accounts, TCP connectivity,
#       application privileges, listening configuration, and initialization
#       marker.
#
#   network
#       Checks the project bridge network, container membership, Docker DNS,
#       internal communication between services, and the shared WordPress volume.
#
#   persistence
#       Creates temporary WordPress file and database records, removes and
#       recreates the containers, verifies that both volumes preserved the data,
#       and removes the temporary test data afterward.
#
#   restart
#       Simulates a real crash of NGINX, WordPress, and MariaDB by killing each
#       main process, then verifies automatic restart and service recovery.
#
#   security
#       Audits Git status and history, ignored secret files, secret-value leaks,
#       container environments, forbidden runtime hacks, latest image tags, and
#       Dockerfile base images.
#
#   cold-start
#       Performs a destructive reset, removes generated TLS files, rebuilds the
#       project from an empty state, and validates initialization and runtime.
#
#   full
#       Runs the complete automated mandatory acceptance suite:
#       cold start, runtime, TLS, WordPress, MariaDB, network, persistence,
#       restart behavior, security audit, and final health checks.
#
# Important:
#
#   The "cold-start" and "full" modes are destructive. They remove the current
#   WordPress and MariaDB data and require explicit confirmation before running.
#
# Examples:
#
#   ./tools/test_mandatory.sh list
#   ./tools/test_mandatory.sh runtime
#   ./tools/test_mandatory.sh persistence
#   ./tools/test_mandatory.sh full
#
# Every run stores the complete evidence output in:
#
#   logs/mandatory-test-YYYYMMDD-HHMMSS.log
#
# ==============================================================================

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

usage() {
    cat <<'USAGE'
Usage:
  ./tools/test_mandatory.sh <mode> [options]

Modes:
  list          List all test modes.
  preflight     Tools, environment, secrets, and Compose structure.
  runtime       Containers, PID 1, configs, HTTPS, and ports.
  tls           Certificate, hostname, key pair, and protocols.
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

parse_options() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --summary)
                VERBOSE=0
                ;;
            --yes)
                ASSUME_YES=1
                ;;
            --no-color)
                NO_COLOR_FLAG=1
                ;;
            -h | --help)
                MODE=help
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                exit 2
                ;;
        esac

        shift
    done
}

validate_mode() {
    case "$MODE" in
        help)
            usage
            exit 0
            ;;
        list)
            list_modes
            exit 0
            ;;
        preflight | runtime | tls | wordpress | mariadb | network | persistence | restart | security | cold-start | full)
            ;;
        *)
            printf 'Unknown mode: %s\n\n' "$MODE" >&2
            usage >&2
            exit 2
            ;;
    esac
}

configure_colors() {
    if [ -t 1 ] && [ "$NO_COLOR_FLAG" -eq 0 ] && [ -z "${NO_COLOR+x}" ]; then
        RESET=$'\033[0m'
        BOLD=$'\033[1m'
        GREEN=$'\033[32m'
        YELLOW=$'\033[33m'
        RED=$'\033[31m'
        CYAN=$'\033[36m'
    else
        RESET=""
        BOLD=""
        GREEN=""
        YELLOW=""
        RED=""
        CYAN=""
    fi
}

cleanup() {
    if [ -n "$PERSIST_ID" ] && docker inspect wordpress >/dev/null 2>&1; then
        docker exec -u www-data wordpress \
            rm -f "/var/www/html/wp-content/${PERSIST_ID}.txt" \
            >/dev/null 2>&1 || true
    fi

    if [ -n "$POST_ID" ] && docker inspect wordpress >/dev/null 2>&1; then
        docker exec -u www-data wordpress \
            wp --path=/var/www/html post delete "$POST_ID" --force \
            >/dev/null 2>&1 || true
    fi

    rm -rf "$TMP_DIR"
}

line() {
    printf '%s\n' \
        '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
}

header() {
    CURRENT="$1"
    TEST_NO=$((TEST_NO + 1))

    if [ "$VERBOSE" -ne 1 ]; then
        return 0
    fi

    printf '\n'
    line
    printf '%bTEST %d — %s%b\n' \
        "$BOLD" \
        "$TEST_NO" \
        "$CURRENT" \
        "$RESET"
    line
}

command_text() {
    if [ "$VERBOSE" -eq 1 ]; then
        printf '\n%bCommand:%b\n  %s\n' \
            "$BOLD" \
            "$RESET" \
            "$1"
    fi
}

evidence() {
    if [ "$VERBOSE" -ne 1 ]; then
        return 0
    fi

    printf '\n%bEvidence:%b\n' "$BOLD" "$RESET"

    if [ -n "${1:-}" ]; then
        printf '%s\n' "$1" | sed 's/^/  /'
    else
        printf '  <no output>\n'
    fi
}

expected() {
    if [ "$VERBOSE" -eq 1 ]; then
        printf '\n%bExpected:%b\n%s\n' \
            "$BOLD" \
            "$RESET" \
            "$(printf '%s\n' "$1" | sed 's/^/  /')"
    fi
}

note() {
    if [ "$VERBOSE" -eq 1 ]; then
        printf '\n%bNote:%b\n%s\n' \
            "$BOLD" \
            "$RESET" \
            "$(printf '%s\n' "$1" | sed 's/^/  /')"
    fi
}

record_result() {
    local status="$1"
    local color="$2"
    local message="$3"

    case "$status" in
        PASS)
            PASS_COUNT=$((PASS_COUNT + 1))
            ;;
        FAIL)
            FAIL_COUNT=$((FAIL_COUNT + 1))
            ;;
        SKIP)
            SKIP_COUNT=$((SKIP_COUNT + 1))
            ;;
    esac

    RESULTS+=("$status|$CURRENT|$message")
    printf '\n%b[%s]%b %s\n' \
        "$color" \
        "$status" \
        "$RESET" \
        "$message"
}

pass() {
    record_result PASS "$GREEN" "$1"
}

fail() {
    record_result FAIL "$RED" "$1"
}

skip() {
    record_result SKIP "$YELLOW" "$1"
}

capture() {
    local shown="$1"

    shift
    command_text "$shown"

    OUT="$("$@" 2>&1)"
    RC=$?

    evidence "$OUT"

    if [ "$VERBOSE" -eq 1 ]; then
        printf '\n%bExit code:%b\n  %d\n' \
            "$BOLD" \
            "$RESET" \
            "$RC"
    fi
}

capture_sh() {
    local shown="$1"
    local code="$2"

    command_text "$shown"

    OUT="$(bash -o pipefail -c "$code" 2>&1)"
    RC=$?

    evidence "$OUT"

    if [ "$VERBOSE" -eq 1 ]; then
        printf '\n%bExit code:%b\n  %d\n' \
            "$BOLD" \
            "$RESET" \
            "$RC"
    fi
}

compose() {
    docker compose -f "$COMPOSE_FILE" "$@"
}

read_env() {
    local key="$1"
    local file
    local value

    shift

    for file in "$@"; do
        if [ ! -r "$file" ]; then
            continue
        fi

        value="$(
            sed -n \
                "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" \
                "$file" \
                | tail -n 1 \
                | tr -d '\r'
        )"

        if [ -n "$value" ]; then
            printf '%s\n' "$value"
            return 0
        fi
    done

    return 1
}

domain() {
    read_env DOMAIN_NAME "$ENV_FILE"
}

db_name() {
    read_env MYSQL_DATABASE "$DATABASE_ENV_FILE"
}

db_user() {
    read_env MYSQL_USER "$DATABASE_ENV_FILE"
}

wp_admin() {
    read_env WP_ADMIN_USER "$WORDPRESS_ENV_FILE"
}

wp_user() {
    read_env WP_USER "$WORDPRESS_ENV_FILE"
}

container_status() {
    docker inspect \
        --format '{{.State.Status}}' \
        "$1" \
        2>/dev/null
}

container_restart_count() {
    docker inspect \
        --format '{{.RestartCount}}' \
        "$1" \
        2>/dev/null
}

container_pid() {
    docker inspect \
        --format '{{.State.Pid}}' \
        "$1" \
        2>/dev/null
}

stack_running() {
    local container
    local status

    for container in "${CONTAINERS[@]}"; do
        status="$(container_status "$container" || true)"

        if [ "$status" != running ]; then
            return 1
        fi
    done

    return 0
}

require_stack() {
    if stack_running; then
        return 0
    fi

    header 'Running stack required'
    capture \
        'docker compose -f srcs/docker-compose.yml ps -a' \
        compose ps -a
    expected 'mariadb, wordpress, and nginx are all running'
    fail 'This mode requires a running Inception stack'

    return 1
}

wait_stack() {
    local timeout="${1:-90}"
    local elapsed=0
    local container
    local status
    local ready

    while [ "$elapsed" -lt "$timeout" ]; do
        ready=1
        OUT=""

        for container in "${CONTAINERS[@]}"; do
            status="$(container_status "$container" || printf missing)"
            OUT+="$container=$status "

            if [ "$status" != running ]; then
                ready=0
            fi
        done

        if [ "$ready" -eq 1 ]; then
            RC=0
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    RC=1
    return 1
}

wait_https() {
    local timeout="${1:-60}"
    local elapsed=0
    local code=""

    while [ "$elapsed" -lt "$timeout" ]; do
        code="$(
            curl \
                -k \
                -sS \
                --connect-timeout 2 \
                -o /dev/null \
                -w '%{http_code}' \
                "https://$(domain)/" \
                2>/dev/null \
                || true
        )"

        if [ "$code" = 200 ]; then
            OUT="HTTPS status=200"
            RC=0
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    OUT="HTTPS status=${code:-connection-failed}"
    RC=1
    return 1
}

confirm_delete() {
    local answer

    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi

    printf '\n%bDESTRUCTIVE TEST WARNING%b\n' \
        "$RED$BOLD" \
        "$RESET"
    printf \
        'This removes containers, images, volumes, certificates, and all data under:\n  %s\n\n' \
        "$DATA_DIR"
    printf 'Type DELETE ALL DATA to continue: '

    IFS= read -r answer

    if [ "$answer" != 'DELETE ALL DATA' ]; then
        printf 'Cancelled.\n'
        exit 2
    fi
}

show_required_project_files() {
    local file

    for file in \
        Makefile \
        srcs/docker-compose.yml \
        srcs/.env \
        srcs/environment/database.env \
        srcs/environment/wordpress.env
    do
        if [ -e "$file" ]; then
            printf 'present: %s\n' "$file"
        else
            printf 'missing: %s\n' "$file"
            return 1
        fi
    done
}

show_required_tool_versions() {
    docker --version
    docker compose version
    python3 --version
    openssl version
    curl --version | head -n 1
    git --version
    make --version | head -n 1
}

show_non_secret_environment() {
    printf '%s\n' '--- srcs/.env ---'
    cat srcs/.env
    printf '%s\n' '--- database.env ---'
    cat srcs/environment/database.env
    printf '%s\n' '--- wordpress.env ---'
    cat srcs/environment/wordpress.env
}

show_compose_architecture() {
    printf '%s\n' 'Services:'
    compose config --services
    printf '%s\n' 'Images:'
    compose config --images
    printf '%s\n' 'Volumes:'
    compose config --volumes
    printf '%s\n' 'Networks:'
    compose config --networks
}

show_container_state() {
    local container

    compose ps -a
    printf '\nDetailed state:\n'

    for container in "${CONTAINERS[@]}"; do
        docker inspect \
            --format '{{.Name}} status={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} exit_code={{.State.ExitCode}}' \
            "$container"
    done
}

show_restart_policies() {
    local container

    for container in "${CONTAINERS[@]}"; do
        docker inspect \
            --format '{{.Name}} policy={{.HostConfig.RestartPolicy.Name}} maximum_retries={{.HostConfig.RestartPolicy.MaximumRetryCount}}' \
            "$container"
    done
}

show_pid1_processes() {
    local container

    for container in "${CONTAINERS[@]}"; do
        printf '%s: ' "$container"
        docker exec "$container" sh -c \
            'tr "\000" " " </proc/1/cmdline; echo'
    done
}

validate_service_configs() {
    docker exec nginx nginx -t
    docker exec wordpress php-fpm8.2 -t
}

show_published_ports() {
    local container

    for container in "${CONTAINERS[@]}"; do
        docker inspect \
            --format '{{.Name}} PortBindings={{json .HostConfig.PortBindings}}' \
            "$container"
    done

    printf '\nHost sockets:\n'
    sudo ss -ltnp | grep -E ':(443|3306|9000)\b' || true
}

show_tls_files() {
    stat \
        -c '%a %U:%G %n' \
        certificates/inception.crt \
        certificates/inception.key

    openssl x509 \
        -in certificates/inception.crt \
        -noout \
        -subject \
        -issuer \
        -dates \
        -ext subjectAltName
}

show_wordpress_installation() {
    docker exec -u www-data wordpress \
        wp --path=/var/www/html core is-installed

    printf 'version='

    docker exec -u www-data wordpress \
        wp --path=/var/www/html core version
}

show_wordpress_options() {
    printf 'siteurl='
    docker exec -u www-data wordpress \
        wp --path=/var/www/html option get siteurl

    printf 'home='
    docker exec -u www-data wordpress \
        wp --path=/var/www/html option get home

    printf 'blogname='
    docker exec -u www-data wordpress \
        wp --path=/var/www/html option get blogname
}

show_wordpress_database_config() {
    local key

    for key in DB_NAME DB_USER DB_HOST; do
        printf '%s=' "$key"
        docker exec -u www-data wordpress \
            wp --path=/var/www/html config get "$key"
    done
}

query_mariadb_databases_and_accounts() {
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
}

query_mariadb_application_connection() {
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
}

query_mariadb_runtime_config() {
    docker exec mariadb sh -c '
        export MYSQL_PWD="$(cat /run/secrets/db_root_password)"

        mariadb \
            --protocol=socket \
            --socket=/run/mysqld/mysqld.sock \
            --user=root \
            --batch \
            --skip-column-names \
            --execute="SELECT @@global.bind_address, @@global.port;"
    '
}

show_network_membership() {
    docker network inspect inception_inception \
        --format 'driver={{.Driver}}
{{range .Containers}}{{.Name}} -> {{.IPv4Address}}{{println}}{{end}}'
}

show_docker_dns() {
    docker exec wordpress getent hosts mariadb
    docker exec nginx getent hosts wordpress
}

show_internal_connectivity() {
    local current_domain

    docker exec wordpress sh -c '
        MYSQL_PWD="$(cat /run/secrets/db_password)" \
            mariadb \
            --protocol=tcp \
            --host="$MYSQL_HOST" \
            --port="$MARIADB_PORT" \
            --user="$MYSQL_USER" \
            --database="$MYSQL_DATABASE" \
            --execute="SELECT 1 AS database_path;"
    '

    current_domain="$(domain)"

    curl \
        -k \
        -sS \
        -o /dev/null \
        -w 'nginx_wordpress_path=%{http_code}\n' \
        "https://$current_domain/"
}

show_wordpress_mounts() {
    local container

    for container in wordpress nginx; do
        printf '%s mounts:\n' "$container"
        docker inspect "$container" \
            --format '{{range .Mounts}}{{println .Name "->" .Destination "RW=" .RW "Source=" .Source}}{{end}}'
    done
}

show_named_volumes() {
    docker volume inspect mariadb_data \
        --format 'name={{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}} options={{json .Options}}'

    docker volume inspect wordpress_data \
        --format 'name={{.Name}} driver={{.Driver}} mountpoint={{.Mountpoint}} options={{json .Options}}'
}

show_git_state() {
    printf 'branch='
    git branch --show-current
    printf 'status:\n'
    git status --short
    printf 'latest_commit:\n'
    git log -1 --oneline
}

show_sensitive_history() {
    git rev-list --objects --all \
        | grep -E '(^| )(secrets/.*\.txt|certificates/.*\.key|credentials\.txt)$' \
        || true

    git log \
        --all \
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
}

show_dockerfile_bases() {
    grep -H '^FROM ' \
        srcs/requirements/mariadb/Dockerfile \
        srcs/requirements/wordpress/Dockerfile \
        srcs/requirements/nginx/Dockerfile
}

show_cold_host_data() {
    sudo find "/home/$(id -un)/data" \
        -maxdepth 2 \
        -printf '%M %u:%g %p\n' \
        | head -n 100
}

show_final_state() {
    local container
    local current_domain

    compose ps -a
    printf '\nContainer details:\n'

    for container in "${CONTAINERS[@]}"; do
        docker inspect \
            --format '{{.Name}} state={{.State.Status}} running={{.State.Running}} restart_count={{.RestartCount}} policy={{.HostConfig.RestartPolicy.Name}}' \
            "$container"
    done

    current_domain="$(domain)"

    printf '\n'
    curl \
        -k \
        -sS \
        -o /dev/null \
        -w 'FINAL HTTPS status=%{http_code}\n' \
        "https://$current_domain/"

    printf '\nGit status:\n'
    git status --short
}

run_preflight() {
    local host
    local port
    local title
    local secret_evidence=""
    local secret_file
    local mode
    local size
    local secrets_valid=1

    header 'Project layout'
    capture 'check required project files' show_required_project_files
    expected 'All required project files are present'

    if [ "$RC" -eq 0 ]; then
        pass 'Required project files are present'
    else
        fail 'One or more required project files are missing'
    fi

    header 'Required command-line tools'
    capture 'print versions for required tools' show_required_tool_versions
    expected 'Every required command prints a version and exits successfully'

    if [ "$RC" -eq 0 ]; then
        pass 'All required command-line tools are available'
    else
        fail 'At least one required tool is unavailable'
    fi

    header 'Docker daemon'
    capture 'docker info' docker info
    expected 'Docker returns server information with exit code 0'

    if [ "$RC" -eq 0 ]; then
        pass 'Docker daemon is running'
    else
        fail 'Docker daemon is unavailable'
    fi

    header 'Non-secret environment configuration'
    capture 'print non-secret environment files' show_non_secret_environment
    expected 'DOMAIN_NAME=tsargsya.42.fr
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_HOST=mariadb
MARIADB_PORT=3306
WP_TITLE=Inception
WP_ADMIN_USER=tsargsya
WP_USER=writer'

    host="$(
        read_env \
            MYSQL_HOST \
            "$DATABASE_ENV_FILE" \
            "$WORDPRESS_ENV_FILE" \
            2>/dev/null \
            || true
    )"
    port="$(read_env MARIADB_PORT "$DATABASE_ENV_FILE" 2>/dev/null || true)"
    title="$(read_env WP_TITLE "$WORDPRESS_ENV_FILE" 2>/dev/null || true)"

    if [ "$(domain 2>/dev/null || true)" = tsargsya.42.fr ] \
        && [ "$(db_name 2>/dev/null || true)" = wordpress ] \
        && [ "$(db_user 2>/dev/null || true)" = wpuser ] \
        && [ "$host" = mariadb ] \
        && [ "$port" = 3306 ] \
        && [ "$title" = Inception ] \
        && [ "$(wp_admin 2>/dev/null || true)" = tsargsya ] \
        && [ "$(wp_user 2>/dev/null || true)" = writer ]
    then
        pass 'Non-secret environment values match the mandatory infrastructure'
    else
        fail 'One or more non-secret environment values are missing or unexpected'
    fi

    header 'Local secret files'

    for secret_file in "${SECRET_FILES[@]}"; do
        if [ -e "$secret_file" ]; then
            mode="$(stat -c '%a' "$secret_file" 2>/dev/null || echo '?')"
            size="$(stat -c '%s' "$secret_file" 2>/dev/null || echo 0)"

            secret_evidence+="${secret_file#"$PROJECT_ROOT/"} mode=$mode size=$size bytes"$'\n'

            if [ ! -s "$secret_file" ]; then
                secrets_valid=0
            fi

            if [ "$mode" != 600 ]; then
                secrets_valid=0
            fi
        else
            secret_evidence+="${secret_file#"$PROJECT_ROOT/"} missing"$'\n'
            secrets_valid=0
        fi
    done

    command_text "stat -c '%a %s %n' secrets/*.txt"
    evidence "${secret_evidence%$'\n'}"
    expected 'All four secrets exist, are non-empty, and have mode 600'
    note 'Secret values are intentionally never printed'

    if [ "$secrets_valid" -eq 1 ]; then
        pass 'All required secret files are present and protected'
    else
        fail 'A secret is missing, empty, or has unsafe permissions'
    fi

    header 'Resolved Compose configuration'
    capture \
        'docker compose -f srcs/docker-compose.yml config' \
        compose config
    expected 'Compose resolves the complete YAML configuration with exit code 0'

    if [ "$RC" -eq 0 ]; then
        pass 'Docker Compose configuration is valid'
    else
        fail 'Docker Compose configuration is invalid'
    fi

    test_compose_architecture
}

test_compose_architecture() {
    local services
    local images
    local volumes
    local networks

    header 'Compose architecture'
    capture \
        'show resolved services, images, volumes, and networks' \
        show_compose_architecture
    expected 'Mandatory services: mariadb, nginx, wordpress
Mandatory images: mariadb:inception, nginx:inception, wordpress:inception
Mandatory volumes: mariadb_data, wordpress_data
Mandatory network: inception
Additional bonus services are ignored by this check'

    services="$(compose config --services 2>/dev/null | sort || true)"
    images="$(compose config --images 2>/dev/null | sort || true)"
    volumes="$(compose config --volumes 2>/dev/null | sort || true)"
    networks="$(compose config --networks 2>/dev/null | sort || true)"

    if grep -Fxq mariadb <<<"$services" \
        && grep -Fxq nginx <<<"$services" \
        && grep -Fxq wordpress <<<"$services" \
        && grep -Fxq mariadb:inception <<<"$images" \
        && grep -Fxq nginx:inception <<<"$images" \
        && grep -Fxq wordpress:inception <<<"$images" \
        && grep -Fxq mariadb_data <<<"$volumes" \
        && grep -Fxq wordpress_data <<<"$volumes" \
        && grep -Fxq inception <<<"$networks"
    then
        pass 'Compose declares the expected mandatory architecture'
    else
        fail 'One or more mandatory Compose resources are missing'
    fi
}

run_runtime() {
    local container
    local restart_policies_valid=1
    local mariadb_pid1
    local wordpress_pid1
    local nginx_pid1
    local mariadb_ports
    local wordpress_ports
    local nginx_ports

    require_stack || return

    header 'Container state'
    capture 'show Compose state and detailed container state' show_container_state
    expected 'All three containers are running; none is Restarting or Exited'

    if stack_running; then
        pass 'All mandatory containers are running'
    else
        fail 'At least one mandatory container is not running'
    fi

    header 'Restart policy configuration'
    capture 'inspect restart policies' show_restart_policies
    expected 'Every container uses restart policy on-failure'

    for container in "${CONTAINERS[@]}"; do
        if [ "$(
            docker inspect \
                --format '{{.HostConfig.RestartPolicy.Name}}' \
                "$container" \
                2>/dev/null \
                || true
        )" != on-failure ]; then
            restart_policies_valid=0
        fi
    done

    if [ "$restart_policies_valid" -eq 1 ]; then
        pass 'All mandatory containers use restart: on-failure'
    else
        fail 'At least one restart policy is unexpected'
    fi

    header 'Main service processes as PID 1'
    capture 'read /proc/1/cmdline in every container' show_pid1_processes
    expected 'MariaDB PID 1 contains mariadbd
WordPress PID 1 contains php-fpm
NGINX PID 1 contains nginx -g daemon off;'

    mariadb_pid1="$(
        docker exec mariadb sh -c \
            'tr "\000" " " </proc/1/cmdline' \
            2>/dev/null \
            || true
    )"
    wordpress_pid1="$(
        docker exec wordpress sh -c \
            'tr "\000" " " </proc/1/cmdline' \
            2>/dev/null \
            || true
    )"
    nginx_pid1="$(
        docker exec nginx sh -c \
            'tr "\000" " " </proc/1/cmdline' \
            2>/dev/null \
            || true
    )"

    if [[ "$mariadb_pid1" == *mariadbd* \
        && "$wordpress_pid1" == *php-fpm* \
        && "$nginx_pid1" == *nginx* \
        && "$nginx_pid1" == *'daemon off;'* ]]
    then
        pass 'The real service process is PID 1 in every container'
    else
        fail 'One or more containers has an unexpected PID 1 process'
    fi

    header 'NGINX and PHP-FPM configuration'
    capture 'nginx -t and php-fpm8.2 -t' validate_service_configs
    expected 'Both configuration tests report success'

    if [ "$RC" -eq 0 ]; then
        pass 'NGINX and PHP-FPM configurations are valid'
    else
        fail 'NGINX or PHP-FPM configuration validation failed'
    fi

    header 'HTTPS home page'
    capture \
        "curl -k https://$(domain)/" \
        curl \
        -k \
        -sS \
        -o /dev/null \
        -w 'status=%{http_code} remote_ip=%{remote_ip} http_version=%{http_version}' \
        "https://$(domain)/"
    expected 'HTTP status 200 through HTTPS'

    if [ "$RC" -eq 0 ] && [[ "$OUT" == status=200* ]]; then
        pass 'The WordPress home page is available through HTTPS'
    else
        fail 'The HTTPS home page did not return status 200'
    fi

    header 'WordPress administrator endpoint'
    capture \
        "curl -k https://$(domain)/wp-admin/" \
        curl \
        -k \
        -sS \
        -o /dev/null \
        -w 'status=%{http_code} redirect=%{redirect_url}' \
        "https://$(domain)/wp-admin/"
    expected 'Unauthenticated /wp-admin/ redirects to wp-login.php'

    if [ "$RC" -eq 0 ] \
        && [[ "$OUT" == status=30[12378]* \
            && "$OUT" == *wp-login.php* ]]
    then
        pass 'WordPress administrator endpoint redirects to login'
    else
        fail 'WordPress administrator endpoint has unexpected behavior'
    fi

    header 'HTTP port 80'
    capture \
        "curl http://$(domain)/ with a 3-second timeout" \
        curl \
        -4 \
        -sS \
        --connect-timeout 3 \
        -o /dev/null \
        "http://$(domain)/"
    expected 'Connection fails because port 80 is not published'

    if [ "$RC" -ne 0 ]; then
        pass 'Port 80 is closed'
    else
        fail 'Port 80 accepts connections'
    fi

    header 'Published host ports'
    capture 'inspect PortBindings and host sockets' show_published_ports
    expected 'MariaDB and WordPress publish no host ports; NGINX publishes only 443'

    mariadb_ports="$(
        docker inspect \
            --format '{{json .HostConfig.PortBindings}}' \
            mariadb \
            2>/dev/null \
            || true
    )"
    wordpress_ports="$(
        docker inspect \
            --format '{{json .HostConfig.PortBindings}}' \
            wordpress \
            2>/dev/null \
            || true
    )"
    nginx_ports="$(
        docker inspect \
            --format '{{json .HostConfig.PortBindings}}' \
            nginx \
            2>/dev/null \
            || true
    )"

    if [ "$mariadb_ports" = '{}' ] \
        && [ "$wordpress_ports" = '{}' ] \
        && [[ "$nginx_ports" == *'"443/tcp"'* \
            && "$nginx_ports" != *'"80/tcp"'* \
            && "$nginx_ports" != *'"3306/tcp"'* \
            && "$nginx_ports" != *'"9000/tcp"'* ]]
    then
        pass 'Only NGINX port 443 is published on the host'
    else
        fail 'Published ports differ from the mandatory architecture'
    fi
}

run_tls() {
    local certificate_mode
    local private_key_mode
    local certificate_metadata
    local certificate_exit
    local private_key_exit
    local diff_output
    local diff_exit

    require_stack || return

    header 'TLS certificate files'
    capture 'stat and inspect generated TLS files' show_tls_files
    expected "Certificate mode 644
Private key mode 600
CN and SAN contain $(domain)"

    certificate_mode="$(stat -c '%a' "$CERTIFICATE_FILE" 2>/dev/null || true)"
    private_key_mode="$(stat -c '%a' "$PRIVATE_KEY_FILE" 2>/dev/null || true)"
    certificate_metadata="$(
        openssl x509 \
            -in "$CERTIFICATE_FILE" \
            -noout \
            -subject \
            -ext subjectAltName \
            2>/dev/null \
            || true
    )"

    if [ -s "$CERTIFICATE_FILE" ] \
        && [ -s "$PRIVATE_KEY_FILE" ] \
        && [ "$certificate_mode" = 644 ] \
        && [ "$private_key_mode" = 600 ] \
        && [[ "$certificate_metadata" == *"$(domain)"* ]]
    then
        pass 'TLS certificate and private key are present and correctly configured'
    else
        fail 'TLS certificate files or metadata are invalid'
    fi

    header 'Certificate hostname'
    capture \
        "openssl x509 -checkhost $(domain)" \
        openssl x509 \
        -in "$CERTIFICATE_FILE" \
        -noout \
        -checkhost "$(domain)"
    expected "Certificate matches hostname $(domain)"

    if [ "$RC" -eq 0 ]; then
        pass 'Certificate matches the configured domain'
    else
        fail 'Certificate does not match the configured domain'
    fi

    header 'Certificate and private-key pair'
    command_text 'extract public keys from certificate and private key, then diff them'

    openssl x509 \
        -in "$CERTIFICATE_FILE" \
        -pubkey \
        -noout \
        >"$TMP_DIR/cert.pub" \
        2>"$TMP_DIR/cert.err"
    certificate_exit=$?

    openssl pkey \
        -in "$PRIVATE_KEY_FILE" \
        -pubout \
        >"$TMP_DIR/key.pub" \
        2>"$TMP_DIR/key.err"
    private_key_exit=$?

    diff_output="$(diff "$TMP_DIR/cert.pub" "$TMP_DIR/key.pub" 2>&1)"
    diff_exit=$?

    evidence "certificate extraction exit=$certificate_exit
private-key extraction exit=$private_key_exit
public-key diff exit=$diff_exit
${diff_output:-public keys are identical}"
    expected 'Both public keys are identical'

    if [ "$certificate_exit" -eq 0 ] \
        && [ "$private_key_exit" -eq 0 ] \
        && [ "$diff_exit" -eq 0 ]
    then
        pass 'Certificate and private key form a matching pair'
    else
        fail 'Certificate and private key do not match'
    fi

    tls_accept TLSv1.2 tls1_2
    tls_accept TLSv1.3 tls1_3
    tls_reject 'TLS 1.0' tls1
    tls_reject 'TLS 1.1' tls1_1
}

tls_accept() {
    local label="$1"
    local flag="$2"

    header "$label support"
    capture_sh \
        "openssl s_client -$flag to $(domain):443" \
        "openssl s_client -brief -connect '$(domain):443' -servername '$(domain)' -$flag </dev/null 2>&1 | grep -E 'Protocol version|Ciphersuite|Verification error'"
    expected "Protocol version: $label"

    if [ "$RC" -eq 0 ] && [[ "$OUT" == *"Protocol version: $label"* ]]; then
        pass "$label is accepted"
    else
        fail "$label is not accepted"
    fi
}

tls_reject() {
    local label="$1"
    local flag="$2"

    header "$label rejection"
    capture_sh \
        "openssl s_client -$flag to $(domain):443" \
        "openssl s_client -brief -connect '$(domain):443' -servername '$(domain)' -$flag -cipher 'ALL:@SECLEVEL=0' </dev/null 2>&1"
    expected "$label handshake fails with a protocol-version alert"

    if [ "$RC" -ne 0 ] \
        && [[ "$OUT" == *'protocol version'* \
            || "$OUT" == *'alert number 70'* ]]
    then
        pass "$label is rejected"
    else
        fail "$label was accepted or rejected unexpectedly"
    fi
}

run_wordpress() {
    local site_url
    local home_url
    local blog_title
    local users_csv
    local administrator
    local second_user

    require_stack || return

    header 'WordPress installation'
    capture 'check WordPress installation and version' show_wordpress_installation
    expected 'WP-CLI confirms that WordPress is installed and prints a version'

    if [ "$RC" -eq 0 ] && [[ "$OUT" == *version=* ]]; then
        pass 'WordPress is installed'
    else
        fail 'WordPress installation check failed'
    fi

    header 'WordPress site options'
    capture 'read siteurl, home, and blogname' show_wordpress_options
    expected "siteurl=https://$(domain)
home=https://$(domain)
blogname=Inception"

    site_url="$(
        docker exec -u www-data wordpress \
            wp --path=/var/www/html option get siteurl \
            2>/dev/null \
            || true
    )"
    home_url="$(
        docker exec -u www-data wordpress \
            wp --path=/var/www/html option get home \
            2>/dev/null \
            || true
    )"
    blog_title="$(
        docker exec -u www-data wordpress \
            wp --path=/var/www/html option get blogname \
            2>/dev/null \
            || true
    )"

    if [ "$site_url" = "https://$(domain)" ] \
        && [ "$home_url" = "https://$(domain)" ] \
        && [ "$blog_title" = Inception ]
    then
        pass 'WordPress site options are correct'
    else
        fail 'WordPress site options are unexpected'
    fi

    header 'WordPress database configuration'
    capture 'read non-secret DB settings through WP-CLI' show_wordpress_database_config
    expected "DB_NAME=$(db_name)
DB_USER=$(db_user)
DB_HOST=mariadb:3306"

    if [[ "$OUT" == *"DB_NAME=$(db_name)"* \
        && "$OUT" == *"DB_USER=$(db_user)"* \
        && "$OUT" == *'DB_HOST=mariadb:3306'* ]]
    then
        pass 'WordPress uses the expected MariaDB connection settings'
    else
        fail 'WordPress database configuration is unexpected'
    fi

    header 'WordPress users and roles'
    capture \
        'wp user list --fields=ID,user_login,user_email,roles' \
        docker exec -u www-data wordpress \
        wp \
        --path=/var/www/html \
        user list \
        --fields=ID,user_login,user_email,roles \
        --format=table
    expected "$(wp_admin) has role administrator
$(wp_user) exists with a non-administrator role
Administrator username does not contain admin"

    administrator="$(wp_admin)"
    second_user="$(wp_user)"
    users_csv="$(
        docker exec -u www-data wordpress \
            wp \
            --path=/var/www/html \
            user list \
            --fields=user_login,roles \
            --format=csv \
            2>/dev/null \
            || true
    )"

    if [[ "$administrator" =~ [Aa][Dd][Mm][Ii][Nn] ]]; then
        fail 'Administrator username contains the forbidden substring admin'
    elif printf '%s\n' "$users_csv" \
        | grep -Eq "^${administrator},administrator$" \
        && printf '%s\n' "$users_csv" \
            | grep -Eq "^${second_user},(author|editor|contributor|subscriber)$"
    then
        pass 'Required WordPress users and roles are configured correctly'
    else
        fail 'Required WordPress users or roles are missing'
    fi
}

run_mariadb() {
    local table_count

    require_stack || return

    header 'MariaDB databases and accounts'
    capture \
        'query databases and mysql.user through the root socket account' \
        query_mariadb_databases_and_accounts
    expected "Database $(db_name) exists
Application account $(db_user)@% exists
Root account exists for localhost"

    if [ "$RC" -eq 0 ] \
        && printf '%s\n' "$OUT" | grep -Fxq "$(db_name)" \
        && printf '%s\n' "$OUT" | grep -Eq "^$(db_user)[[:space:]]+%$" \
        && printf '%s\n' "$OUT" | grep -Eq '^root[[:space:]]+localhost$'
    then
        pass 'MariaDB database and accounts are configured'
    else
        fail 'MariaDB database or required accounts are missing'
    fi

    header 'MariaDB application connection'
    capture \
        'connect as the WordPress database user through TCP' \
        query_mariadb_application_connection
    expected "current_database=$(db_name)
WordPress table count is greater than zero"

    table_count="$(
        printf '%s\n' "$OUT" \
            | awk '/^[0-9]+$/ {value=$1} END {print value}'
    )"

    if [ "$RC" -eq 0 ] \
        && printf '%s\n' "$OUT" | grep -Fxq "$(db_name)" \
        && [[ "$table_count" =~ ^[0-9]+$ ]] \
        && [ "$table_count" -gt 0 ]
    then
        pass 'WordPress database user can access initialized tables'
    else
        fail 'WordPress database user cannot access valid WordPress tables'
    fi

    header 'MariaDB application privileges'
    capture \
        'SHOW GRANTS FOR application user' \
        docker exec mariadb sh -c \
        'MYSQL_PWD="$(cat /run/secrets/db_root_password)" mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock --user=root --execute="SHOW GRANTS FOR '\''$MYSQL_USER'\''@'\''%'\'';"'
    expected "$(db_user) has privileges on $(db_name).*"

    if [ "$RC" -eq 0 ] \
        && [[ "$OUT" == *"$(db_name)"* \
            && "$OUT" == *"$(db_user)"* ]]
    then
        pass 'Application account has privileges on the WordPress database'
    else
        fail 'Application account privileges are missing or unexpected'
    fi

    header 'MariaDB runtime configuration'
    capture 'query bind_address and port' query_mariadb_runtime_config
    expected 'bind_address=0.0.0.0
port=3306'

    if [ "$RC" -eq 0 ] \
        && printf '%s\n' "$OUT" \
            | grep -Eq '^0\.0\.0\.0[[:space:]]+3306$'
    then
        pass 'MariaDB listens on the expected internal address and port'
    else
        fail 'MariaDB bind address or port is unexpected'
    fi

    header 'MariaDB initialization state'
    capture \
        'list system tables, project marker, and WordPress database directory' \
        docker exec mariadb sh -c \
        'ls -ld /var/lib/mysql/mysql /var/lib/mysql/.inception_initialized /var/lib/mysql/wordpress'
    expected 'System tables, initialization marker, and WordPress database directory exist'

    if [ "$RC" -eq 0 ]; then
        pass 'MariaDB persistent initialization state is complete'
    else
        fail 'MariaDB initialization files are incomplete'
    fi
}

run_network() {
    local driver
    local members
    local member_count
    local wordpress_source
    local nginx_source
    local nginx_read_write

    require_stack || return

    header 'Docker network membership'
    capture 'inspect inception_inception' show_network_membership
    expected 'Bridge driver with mariadb, nginx, and wordpress attached; bonus containers may also be present'

    driver="$(
        docker network inspect inception_inception \
            --format '{{.Driver}}' \
            2>/dev/null \
            || true
    )"

    members="$(
        docker network inspect inception_inception \
            --format '{{range .Containers}}{{println .Name}}{{end}}' \
            2>/dev/null \
            | sed '/^[[:space:]]*$/d' \
            | sort -u
    )"

    member_count="$(
        printf '%s\n' "$members" \
            | sed '/^[[:space:]]*$/d' \
            | wc -l \
            | tr -d '[:space:]'
    )"

    if [ "$driver" = bridge ] \
        && [ "$member_count" -ge 3 ] \
        && grep -Fxq mariadb <<<"$members" \
        && grep -Fxq wordpress <<<"$members" \
        && grep -Fxq nginx <<<"$members"
    then
        pass 'All mandatory containers share the project bridge network'
    else
        fail 'Mandatory Docker network membership or driver is unexpected'
    fi

    header 'Docker DNS'
    capture \
        'resolve mariadb from WordPress and wordpress from NGINX' \
        show_docker_dns
    expected 'WordPress resolves mariadb
NGINX resolves wordpress'

    if [ "$RC" -eq 0 ] \
        && printf '%s\n' "$OUT" | grep -Eq '[[:space:]]mariadb$' \
        && printf '%s\n' "$OUT" | grep -Eq '[[:space:]]wordpress$'
    then
        pass 'Docker DNS resolves internal service names'
    else
        fail 'Docker DNS resolution failed'
    fi

    header 'Internal service connectivity'
    capture \
        'query MariaDB from WordPress and the website through NGINX' \
        show_internal_connectivity
    expected 'WordPress reaches mariadb:3306
NGINX reaches WordPress and returns HTTP 200'

    if [ "$RC" -eq 0 ] \
        && printf '%s\n' "$OUT" | grep -Fxq 1 \
        && printf '%s\n' "$OUT" | grep -Fxq 'nginx_wordpress_path=200'
    then
        pass 'The complete internal request path is operational'
    else
        fail 'Internal service connectivity is broken'
    fi

    header 'Shared WordPress volume'
    capture 'inspect WordPress and NGINX mounts' show_wordpress_mounts
    expected 'WordPress and NGINX use the same /var/www/html source
NGINX mount is read-only'

    wordpress_source="$(
        docker inspect wordpress \
            --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}' \
            2>/dev/null \
            || true
    )"
    nginx_source="$(
        docker inspect nginx \
            --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.Source}}{{end}}{{end}}' \
            2>/dev/null \
            || true
    )"
    nginx_read_write="$(
        docker inspect nginx \
            --format '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{.RW}}{{end}}{{end}}' \
            2>/dev/null \
            || true
    )"

    if [ -n "$wordpress_source" ] \
        && [ "$wordpress_source" = "$nginx_source" ] \
        && [ "$nginx_read_write" = false ]
    then
        pass 'WordPress files are shared with NGINX through a read-only mount'
    else
        fail 'WordPress shared-volume mounts are unexpected'
    fi
}

persistence_file_path() {
    printf '/var/www/html/wp-content/%s.txt\n' "$PERSIST_ID"
}

read_container_persistence_file() {
    docker exec wordpress \
        cat "$(persistence_file_path)" \
        2>/dev/null
}

read_host_persistence_file() {
    sudo cat \
        "$WORDPRESS_DATA_DIR/wp-content/${PERSIST_ID}.txt" \
        2>/dev/null
}

get_persistence_post() {
    docker exec -u www-data wordpress \
        wp \
        --path=/var/www/html \
        post get "$POST_ID" \
        --fields=ID,post_title,post_status \
        --format=table \
        2>/dev/null
}

run_persistence() {
    local file_create_exit
    local post_create_exit
    local container_value
    local host_value
    local post_evidence
    local down_output
    local down_exit
    local containers_after_down
    local volumes_after_down
    local host_value_after_down
    local database_after_down
    local make_output
    local make_exit
    local stack_exit
    local stack_output
    local https_exit
    local https_output
    local users
    local mariadb_logs
    local wordpress_logs
    local initialization_markers
    local delete_post_output
    local delete_post_exit
    local delete_file_output
    local delete_file_exit
    local file_exists=0
    local post_exists=0

    require_stack || return

    header 'Create persistence evidence'

    PERSIST_ID="persistence-$(date '+%Y%m%d-%H%M%S')"
    command_text 'create a WordPress volume file and a draft database record'

    docker exec -u www-data wordpress sh -c \
        "printf '%s\n' '$PERSIST_ID' > '$(persistence_file_path)'" \
        >"$TMP_DIR/file-create.log" \
        2>&1
    file_create_exit=$?

    POST_ID="$(
        docker exec -u www-data wordpress \
            wp \
            --path=/var/www/html \
            post create \
            --post_type=post \
            --post_status=draft \
            --post_title="$PERSIST_ID" \
            --porcelain \
            2>"$TMP_DIR/post-create.log"
    )"
    post_create_exit=$?

    container_value="$(read_container_persistence_file || true)"
    host_value="$(read_host_persistence_file || true)"
    post_evidence="$(get_persistence_post || true)"

    evidence "test_id=$PERSIST_ID
post_id=$POST_ID
container_file=$container_value
host_file=$host_value
$post_evidence
$(cat "$TMP_DIR/file-create.log" "$TMP_DIR/post-create.log" 2>/dev/null || true)"
    expected 'The same unique value exists in the container, host volume, and draft post'

    if [ "$file_create_exit" -eq 0 ] \
        && [ "$post_create_exit" -eq 0 ] \
        && [ -n "$POST_ID" ] \
        && [ "$container_value" = "$PERSIST_ID" ] \
        && [ "$host_value" = "$PERSIST_ID" ] \
        && [[ "$post_evidence" == *"$PERSIST_ID"* \
            && "$post_evidence" == *draft* ]]
    then
        pass 'Persistence test data was created in both volumes'
    else
        fail 'Could not create valid persistence test data'
        return
    fi

    header 'Named volume configuration'
    capture 'inspect mariadb_data and wordpress_data' show_named_volumes
    expected "mariadb_data uses $MARIADB_DATA_DIR
wordpress_data uses $WORDPRESS_DATA_DIR"

    if [ "$RC" -eq 0 ] \
        && [[ "$OUT" == *"$MARIADB_DATA_DIR"* \
            && "$OUT" == *"$WORDPRESS_DATA_DIR"* ]]
    then
        pass 'Named volumes use the expected host directories'
    else
        fail 'Named volume backing directories are unexpected'
    fi

    header 'Remove containers without deleting persistent data'
    capture 'make down' make down

    down_output="$OUT"
    down_exit="$RC"
    containers_after_down="$(compose ps -a 2>&1 || true)"
    volumes_after_down="$(
        docker volume ls \
            --format '{{.Name}}' \
            | grep -E '^(mariadb_data|wordpress_data)$' \
            | sort \
            || true
    )"
    host_value_after_down="$(read_host_persistence_file || true)"
    database_after_down="$(
        if sudo test -d "$MARIADB_DATA_DIR/wordpress"; then
            printf 'present\n'
        else
            printf 'missing\n'
        fi
    )"

    evidence "$down_output

Containers after make down:
$containers_after_down

Volumes after make down:
$volumes_after_down

Host WordPress file:
$host_value_after_down

MariaDB database directory:
$database_after_down"
    expected 'Containers are removed
Both named volumes remain
WordPress test file remains
MariaDB database directory remains'

    if [ "$down_exit" -eq 0 ] \
        && [ -z "$(compose ps -aq 2>/dev/null || true)" ] \
        && [ "$volumes_after_down" = $'mariadb_data\nwordpress_data' ] \
        && [ "$host_value_after_down" = "$PERSIST_ID" ] \
        && [ "$database_after_down" = present ]
    then
        pass 'Persistent data survived container removal'
    else
        fail 'Persistent data or named volumes were lost after make down'
    fi

    header 'Recreate containers with preserved volumes'
    capture 'make' make

    make_output="$OUT"
    make_exit="$RC"

    wait_stack 120
    stack_exit="$RC"
    stack_output="$OUT"

    wait_https 90
    https_exit="$RC"
    https_output="$OUT"

    evidence "$make_output

Stack readiness:
$stack_output

Endpoint readiness:
$https_output"
    expected 'make succeeds, all containers run, and HTTPS returns 200'

    if [ "$make_exit" -eq 0 ] \
        && [ "$stack_exit" -eq 0 ] \
        && [ "$https_exit" -eq 0 ]
    then
        pass 'Containers were recreated successfully with preserved volumes'
    else
        fail 'Container recreation or service readiness failed'
        return
    fi

    header 'Verify preserved WordPress and MariaDB data'

    container_value="$(read_container_persistence_file || true)"
    host_value="$(read_host_persistence_file || true)"
    post_evidence="$(get_persistence_post || true)"
    users="$(
        docker exec -u www-data wordpress \
            wp \
            --path=/var/www/html \
            user list \
            --fields=ID,user_login,roles \
            --format=table \
            2>/dev/null \
            || true
    )"

    command_text 'read the original file and draft after container recreation'
    evidence "expected=$PERSIST_ID
container_file=$container_value
host_file=$host_value

Database draft:
$post_evidence

WordPress users:
$users"
    expected 'The original unique file value and draft record are unchanged'

    if [ "$container_value" = "$PERSIST_ID" ] \
        && [ "$host_value" = "$PERSIST_ID" ] \
        && [[ "$post_evidence" == *"$PERSIST_ID"* \
            && "$post_evidence" == *draft* ]]
    then
        pass 'WordPress files and MariaDB records survived container recreation'
    else
        fail 'WordPress or MariaDB persistence verification failed'
    fi

    header 'Initialization idempotency'

    mariadb_logs="$(compose logs --no-color mariadb 2>&1 || true)"
    wordpress_logs="$(compose logs --no-color wordpress 2>&1 || true)"
    initialization_markers="$(
        printf '%s\n' "$mariadb_logs" \
            | grep -E 'Initializing MariaDB|Configuring the Inception|initialization completed' \
            || true
    )"

    command_text 'inspect MariaDB and WordPress logs after preserved-volume startup'
    evidence "MariaDB initialization markers:
${initialization_markers:-<none>}

WordPress startup:
$wordpress_logs"
    expected 'MariaDB full initialization is absent
WordPress reports existing files, installation, and second user'

    if [ -z "$initialization_markers" ] \
        && [[ "$wordpress_logs" == *'WordPress files already exist.'* \
            && "$wordpress_logs" == *'WordPress is already installed.'* \
            && "$wordpress_logs" == *'Second WordPress user already exists.'* ]]
    then
        pass 'Preserved data prevents repeated initialization'
    else
        fail 'MariaDB or WordPress initialization was unexpectedly repeated'
    fi

    header 'Remove persistence test data'
    command_text 'delete the temporary draft and volume file'

    delete_post_output="$(
        docker exec -u www-data wordpress \
            wp \
            --path=/var/www/html \
            post delete "$POST_ID" \
            --force \
            2>&1
    )"
    delete_post_exit=$?

    delete_file_output="$(
        docker exec -u www-data wordpress \
            rm -f "$(persistence_file_path)" \
            2>&1
    )"
    delete_file_exit=$?

    if docker exec wordpress test -e "$(persistence_file_path)" \
        >/dev/null 2>&1
    then
        file_exists=1
    fi

    if docker exec -u www-data wordpress \
        wp --path=/var/www/html post get "$POST_ID" \
        >/dev/null 2>&1
    then
        post_exists=1
    fi

    evidence "draft deletion exit=$delete_post_exit
$delete_post_output
file deletion exit=$delete_file_exit
$delete_file_output
file_exists_after_cleanup=$file_exists
post_exists_after_cleanup=$post_exists"
    expected 'Temporary draft and volume file are both removed'

    if [ "$delete_post_exit" -eq 0 ] \
        && [ "$delete_file_exit" -eq 0 ] \
        && [ "$file_exists" -eq 0 ] \
        && [ "$post_exists" -eq 0 ]
    then
        PERSIST_ID=""
        POST_ID=""
        pass 'Persistence test data was removed'
    else
        fail 'Persistence test cleanup was incomplete'
    fi
}

wait_for_container_restart() {
    local container="$1"
    local before="$2"
    local attempt=0

    RESTART_STATE=unknown
    RESTART_COUNT="$before"
    RESTART_TRANSITIONS=""

    while [ "$attempt" -lt 30 ]; do
        RESTART_STATE="$(container_status "$container" || echo missing)"
        RESTART_COUNT="$(container_restart_count "$container" || echo 0)"
        RESTART_TRANSITIONS+="attempt $attempt: state=$RESTART_STATE restart_count=$RESTART_COUNT"$'\n'

        if [ "$RESTART_STATE" = running ] \
            && [ "$RESTART_COUNT" -gt "$before" ]
        then
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 1
    done

    return 1
}

probe_https_recovery() {
    local output
    local exit_code

    sleep 2

    output="$(
        curl \
            -k \
            -sS \
            -o /dev/null \
            -w 'HTTPS status=%{http_code}' \
            "https://$(domain)/" \
            2>&1
    )"
    exit_code=$?

    printf '%s\n' "$output"

    if [ "$exit_code" -eq 0 ] && [[ "$output" == *'status=200'* ]]; then
        return 0
    fi

    return 1
}

probe_wordpress_recovery() {
    local output
    local exit_code

    sleep 3

    output="$(
        docker exec -u www-data wordpress \
            wp --path=/var/www/html core is-installed \
            2>&1
    )"
    exit_code=$?

    if [ -n "$output" ]; then
        printf '%s\n' "$output"
    fi

    if [ "$exit_code" -eq 0 ]; then
        printf '%s\n' 'WordPress core is installed'
        return 0
    fi

    return 1
}

probe_mariadb_recovery() {
    local probe=0
    local output
    local exit_code=1

    while [ "$probe" -lt 30 ]; do
        output="$(
            docker exec mariadb sh -c '
                MYSQL_PWD="$(cat /run/secrets/db_password)" \
                    mariadb \
                    --protocol=tcp \
                    --connect-timeout=2 \
                    --host=127.0.0.1 \
                    --port="$MARIADB_PORT" \
                    --user="$MYSQL_USER" \
                    --database="$MYSQL_DATABASE" \
                    --execute="SELECT 1 AS database_available;"
            ' 2>&1
        )"
        exit_code=$?

        if [ "$exit_code" -eq 0 ]; then
            printf '%s\n' "$output"
            return 0
        fi

        sleep 1
        probe=$((probe + 1))
    done

    printf '%s\n' "$output"
    return "$exit_code"
}

probe_recovered_service() {
    local kind="$1"

    case "$kind" in
        https)
            probe_https_recovery
            ;;
        wordpress)
            probe_wordpress_recovery
            ;;
        mariadb)
            probe_mariadb_recovery
            ;;
        *)
            printf 'Unknown service probe: %s\n' "$kind" >&2
            return 1
            ;;
    esac
}

crash_one() {
    local container="$1"
    local kind="$2"
    local restart_count_before
    local host_pid
    local kill_exit
    local service_output
    local service_exit

    header "$container automatic crash restart"

    restart_count_before="$(container_restart_count "$container" || echo 0)"
    host_pid="$(container_pid "$container" || echo 0)"

    command_text "sudo kill -KILL host PID $host_pid for $container"

    sudo kill -KILL "$host_pid" \
        >"$TMP_DIR/$container-kill.log" \
        2>&1
    kill_exit=$?

    wait_for_container_restart "$container" "$restart_count_before" || true

    service_output="$(probe_recovered_service "$kind" 2>&1)"
    service_exit=$?

    evidence "host_pid=$host_pid
restart_count_before=$restart_count_before
kill_exit=$kill_exit
$(cat "$TMP_DIR/$container-kill.log" 2>/dev/null || true)

Observed transitions:
${RESTART_TRANSITIONS%$'\n'}

Final state:
state=$RESTART_STATE
restart_count_after=$RESTART_COUNT

Service verification:
$service_output"
    expected 'Host PID is killed unexpectedly
RestartCount increases
Container returns to running
Service-specific verification succeeds'

    if [ "$kill_exit" -eq 0 ] \
        && [ "$RESTART_STATE" = running ] \
        && [ "$RESTART_COUNT" -gt "$restart_count_before" ] \
        && [ "$service_exit" -eq 0 ]
    then
        pass "$container restarted automatically and recovered its service"
    else
        fail "$container did not recover correctly after its main process crashed"
    fi
}

run_restart() {
    require_stack || return

    header 'Privilege check for crash simulation'
    capture 'sudo -v' sudo -v
    expected 'sudo authentication succeeds'

    if [ "$RC" -eq 0 ]; then
        pass 'Required privileges are available for crash simulation'
    else
        fail 'sudo privileges are unavailable'
        return
    fi

    printf '\nWaiting 10 seconds so restart policies are fully active...\n'
    sleep 10

    crash_one nginx https
    crash_one wordpress wordpress
    crash_one mariadb mariadb

    header 'Website after all crash tests'
    wait_https 60
    command_text "curl -k https://$(domain)/"
    evidence "$OUT"
    expected 'Final HTTPS status is 200'

    if [ "$RC" -eq 0 ]; then
        pass 'Website works after all service crash recoveries'
    else
        fail 'Website did not recover after the crash sequence'
    fi
}

run_security() {
    local git_status
    local tracked_files
    local secret_evidence=""
    local secret_file
    local secret_value
    local secrets_valid=1
    local container
    local found
    local environment_evidence=""
    local environments_valid=1
    local dockerfile_lines
    local dockerfile_count

    header 'Git working tree'
    capture 'show branch, status, and latest commit' show_git_state
    expected 'Branch main and no output from git status --short'

    git_status="$(git status --short 2>/dev/null || true)"

    if [ "$(git branch --show-current 2>/dev/null || true)" = main ] \
        && [ -z "$git_status" ]
    then
        pass 'Git working tree is clean on main'
    else
        fail 'Git working tree is not clean on main'
    fi

    header 'Tracked secret and certificate paths'
    capture \
        'git ls-files secrets certificates' \
        git ls-files secrets certificates
    expected 'Only certificates/.gitkeep and secrets/.gitkeep are tracked'

    tracked_files="$(printf '%s\n' "$OUT" | sort)"

    if [ "$tracked_files" = $'certificates/.gitkeep\nsecrets/.gitkeep' ]; then
        pass 'No generated secret or TLS payload is tracked'
    else
        fail 'Unexpected files under secrets or certificates are tracked'
    fi

    header 'Git ignore rules for secrets and certificates'
    capture \
        'git check-ignore -v required generated files' \
        git check-ignore -v \
        secrets/db_root_password.txt \
        secrets/db_password.txt \
        secrets/wp_admin_password.txt \
        secrets/wp_user_password.txt \
        certificates/inception.crt \
        certificates/inception.key
    expected 'All six generated files match .gitignore rules'

    if [ "$RC" -eq 0 ] \
        && [ "$(printf '%s\n' "$OUT" | sed '/^$/d' | wc -l)" -eq 6 ]
    then
        pass 'Secrets and generated TLS files are ignored by Git'
    else
        fail 'One or more sensitive files is not ignored'
    fi

    header 'Sensitive paths in Git history'
    capture \
        'search all Git objects and history for sensitive paths' \
        show_sensitive_history
    expected 'No output'

    if [ -z "$OUT" ]; then
        pass 'No secret file or private-key path exists in Git history'
    else
        fail 'A sensitive path exists in Git history'
    fi

    header 'Current secret values in tracked files'

    for secret_file in "${SECRET_FILES[@]}"; do
        secret_value="$(tr -d '\r\n' <"$secret_file" 2>/dev/null || true)"

        if [ -z "$secret_value" ]; then
            secret_evidence+="${secret_file#"$PROJECT_ROOT/"}: empty"$'\n'
            secrets_valid=0
        elif git grep -F -q -e "$secret_value" --; then
            secret_evidence+="${secret_file#"$PROJECT_ROOT/"}: value found in tracked files"$'\n'
            secrets_valid=0
        else
            secret_evidence+="${secret_file#"$PROJECT_ROOT/"}: value absent from tracked files"$'\n'
        fi
    done

    command_text 'compare each secret value against tracked files without printing it'
    evidence "${secret_evidence%$'\n'}"
    expected 'Every secret value is absent from tracked files'
    note 'Actual secret values are never printed'

    if [ "$secrets_valid" -eq 1 ]; then
        pass 'Current secret values are absent from tracked files'
    else
        fail 'A secret is empty or appears in a tracked file'
    fi

    if stack_running; then
        header 'Password values in container environments'

        for container in "${CONTAINERS[@]}"; do
            found="$(
                docker inspect \
                    --format '{{range .Config.Env}}{{println .}}{{end}}' \
                    "$container" \
                    2>/dev/null \
                    | grep -Ei '(PASSWORD|PASSWD|SECRET)=' \
                    || true
            )"

            if [ -n "$found" ]; then
                environment_evidence+="$container:"$'\n'"$found"$'\n'
                environments_valid=0
            else
                environment_evidence+="$container: no password values in environment"$'\n'
            fi
        done

        command_text 'inspect container environments for password-like keys'
        evidence "${environment_evidence%$'\n'}"
        expected 'No password or secret value is passed through environment variables'

        if [ "$environments_valid" -eq 1 ]; then
            pass 'Container environments do not contain password values'
        else
            fail 'A password-like value is present in a container environment'
        fi
    else
        header 'Password values in container environments'
        skip 'Container environment audit requires a running stack'
    fi

    header 'Forbidden container runtime patterns'
    capture_sh \
        'grep Docker sources for forbidden runtime hacks' \
        'grep -RInE "tail[[:space:]]+-f|sleep[[:space:]]+infinity|while[[:space:]]+(true|:)|network_mode:[[:space:]]*host|^[[:space:]]*links:" srcs || true'
    expected 'No output'

    if [ -z "$OUT" ]; then
        pass 'No forbidden container runtime hack was found'
    else
        fail 'A forbidden container runtime pattern was found'
    fi

    header 'Latest image tags'
    capture_sh \
        'search Docker sources for :latest' \
        'grep -RInE "FROM[[:space:]]+[^[:space:]]*:latest|image:[[:space:]]*[^[:space:]]*:latest" srcs || true'
    expected 'No output'

    if [ -z "$OUT" ]; then
        pass 'No latest image tag is used'
    else
        fail 'A latest image tag is used'
    fi

    header 'Dockerfile base images'
    capture \
        'print mandatory Dockerfile FROM instructions' \
        show_dockerfile_bases
    expected 'The three mandatory Dockerfiles each use FROM debian:bookworm; bonus Dockerfiles are ignored'

    dockerfile_lines="$(printf '%s\n' "$OUT" | sed '/^$/d')"
    dockerfile_count="$(printf '%s\n' "$dockerfile_lines" | wc -l)"

    if [ "$RC" -eq 0 ] \
        && [ "$dockerfile_count" -eq 3 ] \
        && ! printf '%s\n' "$dockerfile_lines" \
            | grep -v 'FROM debian:bookworm' \
            >/dev/null
    then
        pass 'All mandatory custom images use the expected Debian base'
    else
        fail 'Mandatory Dockerfile base images are unexpected'
    fi

    test_compose_architecture
}

cold_logs() {
    local mariadb_logs
    local wordpress_logs
    local nginx_logs

    header 'Cold-start service logs'

    mariadb_logs="$(compose logs --no-color mariadb 2>&1 || true)"
    wordpress_logs="$(compose logs --no-color wordpress 2>&1 || true)"
    nginx_logs="$(compose logs --no-color nginx 2>&1 || true)"

    command_text 'docker compose logs for mariadb, wordpress, and nginx'
    evidence "===== MariaDB =====
$mariadb_logs

===== WordPress =====
$wordpress_logs

===== NGINX =====
$nginx_logs"
    expected 'MariaDB initializes and becomes ready
WordPress installs and creates the second user
NGINX configuration test succeeds'

    if [[ "$mariadb_logs" == *'ready for connections'* \
        && "$wordpress_logs" == *'WordPress installed.'* \
        && "$wordpress_logs" == *'Second WordPress user created.'* \
        && "$nginx_logs" == *'test is successful'* ]]
    then
        pass 'Cold-start logs confirm successful initialization of all services'
    else
        fail 'Cold-start logs do not contain all expected initialization evidence'
    fi
}

cold_domain() {
    header 'Local domain resolution'
    capture_sh \
        "getent hosts and inspect /etc/hosts for $(domain)" \
        "getent hosts '$(domain)'; grep -n '$(domain)' /etc/hosts"
    expected "$(domain) resolves to 127.0.0.1"

    if [ "$RC" -eq 0 ] \
        && printf '%s\n' "$OUT" \
            | grep -Eq "127\.0\.0\.1[[:space:]]+$(domain)"
    then
        pass 'Project domain resolves to the local VM'
    else
        fail 'Project domain does not resolve to 127.0.0.1'
    fi
}

cold_host_data() {
    header 'Persistent host data layout'
    capture \
        'inspect MariaDB and WordPress host directories' \
        show_cold_host_data
    expected 'MariaDB system/database directories and WordPress core directories exist'

    if [ "$RC" -eq 0 ] \
        && sudo test -d "$MARIADB_DATA_DIR/mysql" \
        && sudo test -d "$MARIADB_DATA_DIR/wordpress" \
        && sudo test -f "$MARIADB_DATA_DIR/.inception_initialized" \
        && sudo test -d "$WORDPRESS_DATA_DIR/wp-admin" \
        && sudo test -d "$WORDPRESS_DATA_DIR/wp-content" \
        && sudo test -d "$WORDPRESS_DATA_DIR/wp-includes" \
        && sudo test -f "$WORDPRESS_DATA_DIR/wp-config.php"
    then
        pass 'Persistent host directories contain initialized MariaDB and WordPress data'
    else
        fail 'Persistent host data layout is incomplete'
    fi
}

cleanup_state_evidence() {
    printf 'containers:\n%s\n\n' "$(compose ps -a 2>&1 || true)"
    printf 'images:\n%s\n\n' "$({
        docker image ls \
            --format '{{.Repository}}:{{.Tag}}' \
            | grep -E '^(mariadb|wordpress|nginx):inception$' \
            || true
    })"
    printf 'volumes:\n%s\n\n' "$({
        docker volume ls \
            --format '{{.Name}}' \
            | grep -E '^(mariadb_data|wordpress_data)$' \
            || true
    })"
    printf 'network:\n%s\n\n' "$({
        docker network ls \
            --format '{{.Name}}' \
            | grep '^inception_inception$' \
            || true
    })"

    if [ -e "$DATA_DIR" ]; then
        printf 'host_data:\npresent\n'
    else
        printf 'host_data:\nremoved\n'
    fi
}

cleanup_state_is_empty() {
    [ -z "$(compose ps -aq 2>/dev/null || true)" ] \
        && [ -z "$(
            docker image ls \
                --format '{{.Repository}}:{{.Tag}}' \
                | grep -E '^(mariadb|wordpress|nginx):inception$' \
                || true
        )" ] \
        && [ -z "$(
            docker volume ls \
                --format '{{.Name}}' \
                | grep -E '^(mariadb_data|wordpress_data)$' \
                || true
        )" ] \
        && [ -z "$(
            docker network ls \
                --format '{{.Name}}' \
                | grep '^inception_inception$' \
                || true
        )" ] \
        && [ ! -e "$DATA_DIR" ]
}

run_cold_start() {
    local cleanup_evidence
    local make_output
    local make_exit
    local stack_exit
    local stack_output
    local https_exit
    local https_output

    confirm_delete

    header 'Complete project cleanup'
    capture 'make fclean' make fclean
    expected 'Project containers, images, volumes, network, and host data are removed'

    if [ "$RC" -eq 0 ]; then
        pass 'make fclean completed successfully'
    else
        fail 'make fclean failed'
    fi

    header 'Cleanup verification'

    cleanup_evidence="$(cleanup_state_evidence)"

    command_text 'inspect containers, images, volumes, network, and host data after fclean'
    evidence "$cleanup_evidence"
    expected 'No project containers, images, volumes, network, or host data directory'

    if cleanup_state_is_empty; then
        pass 'Complete cleanup state is correct'
    else
        fail 'Cleanup left infrastructure or data behind'
    fi

    header 'Remove generated TLS files'
    command_text 'rm -f certificates/inception.crt certificates/inception.key'

    rm -f "$CERTIFICATE_FILE" "$PRIVATE_KEY_FILE"

    evidence "$(ls -la certificates 2>&1 || true)"
    expected 'Generated certificate and private key are absent'

    if [ ! -e "$CERTIFICATE_FILE" ] && [ ! -e "$PRIVATE_KEY_FILE" ]; then
        pass 'Generated TLS files were removed for a true cold start'
    else
        fail 'Generated TLS files could not be removed'
    fi

    header 'Cold build and startup'
    capture 'make' make

    make_output="$OUT"
    make_exit="$RC"

    wait_stack 120
    stack_exit="$RC"
    stack_output="$OUT"

    wait_https 90
    https_exit="$RC"
    https_output="$OUT"

    evidence "$make_output

Stack readiness:
$stack_output

Endpoint readiness:
$https_output"
    expected 'make succeeds, all containers run, and HTTPS returns 200'

    if [ "$make_exit" -eq 0 ] \
        && [ "$stack_exit" -eq 0 ] \
        && [ "$https_exit" -eq 0 ]
    then
        pass 'The complete infrastructure started successfully from an empty state'
    else
        fail 'Cold build or startup failed'
    fi

    if stack_running; then
        cold_logs
        cold_domain
        cold_host_data
    else
        header 'Cold-start continuation'
        skip 'Cold-start validation requires all containers to be running'
    fi
}

final_state() {
    local https_code
    local git_status

    header 'Final acceptance state'
    capture \
        'show final containers, policies, HTTPS, and Git state' \
        show_final_state
    expected 'All containers running with on-failure
HTTPS status 200
Clean Git working tree'

    https_code="$(
        curl \
            -k \
            -sS \
            -o /dev/null \
            -w '%{http_code}' \
            "https://$(domain)/" \
            2>/dev/null \
            || true
    )"
    git_status="$(git status --short 2>/dev/null || true)"

    if stack_running \
        && [ "$https_code" = 200 ] \
        && [ -z "$git_status" ]
    then
        pass 'Final mandatory acceptance state is healthy'
    else
        fail 'Final mandatory acceptance state is not clean and healthy'
    fi
}

summary() {
    local result
    local status
    local name
    local message

    printf '\n'
    line
    printf '%bMANDATORY TEST SUMMARY%b\n' "$BOLD" "$RESET"
    line
    printf '\n'

    for result in "${RESULTS[@]}"; do
        IFS='|' read -r status name message <<<"$result"

        case "$status" in
            PASS)
                printf '%b[PASS]%b %s — %s\n' \
                    "$GREEN" \
                    "$RESET" \
                    "$name" \
                    "$message"
                ;;
            FAIL)
                printf '%b[FAIL]%b %s — %s\n' \
                    "$RED" \
                    "$RESET" \
                    "$name" \
                    "$message"
                ;;
            SKIP)
                printf '%b[SKIP]%b %s — %s\n' \
                    "$YELLOW" \
                    "$RESET" \
                    "$name" \
                    "$message"
                ;;
        esac
    done

    printf '\nPassed:  %d\nFailed:  %d\nSkipped: %d\n\n' \
        "$PASS_COUNT" \
        "$FAIL_COUNT" \
        "$SKIP_COUNT"

    if [ "$FAIL_COUNT" -eq 0 ]; then
        printf '%bRESULT: PASS%b\n' "$GREEN$BOLD" "$RESET"
    else
        printf '%bRESULT: FAIL%b\n' "$RED$BOLD" "$RESET"
    fi

    printf 'Full evidence log:\n  %s\n' "$LOG_FILE"
}

run_cold_start_suite() {
    run_preflight

    if [ "$FAIL_COUNT" -ne 0 ]; then
        header 'Destructive cold-start continuation'
        skip 'Cold-start was not executed because preflight checks failed'
        return
    fi

    run_cold_start

    if stack_running; then
        run_runtime
        run_tls
        run_wordpress
        run_mariadb
        run_network
    fi

    final_state
}

run_full_suite() {
    run_preflight

    if [ "$FAIL_COUNT" -ne 0 ]; then
        header 'Destructive full-suite continuation'
        skip 'The destructive suite was not executed because preflight checks failed'
        run_security
        return
    fi

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
        header 'Full-suite runtime continuation'
        skip 'Runtime tests were skipped because the cold-start stack is not running'
    fi

    run_security
    final_state
}

run_selected_mode() {
    case "$MODE" in
        preflight)
            run_preflight
            ;;
        runtime)
            run_runtime
            ;;
        tls)
            run_tls
            ;;
        wordpress)
            run_wordpress
            ;;
        mariadb)
            run_mariadb
            ;;
        network)
            run_network
            ;;
        persistence)
            run_persistence
            ;;
        restart)
            run_restart
            ;;
        security)
            run_security
            ;;
        cold-start)
            run_cold_start_suite
            ;;
        full)
            run_full_suite
            ;;
    esac
}

parse_options "$@"
validate_mode
configure_colors

mkdir -p "$PROJECT_ROOT/logs"
LOG_FILE="$PROJECT_ROOT/logs/mandatory-test-$(date '+%Y%m%d-%H%M%S').log"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/inception-test.XXXXXX")"

trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

exec > >(tee -a "$LOG_FILE") 2>&1
cd "$PROJECT_ROOT"

printf '%bInception Mandatory Test Runner%b\n' "$CYAN$BOLD" "$RESET"
printf 'Project root: %s\nMode:         %s\nEvidence log: %s\n' \
    "$PROJECT_ROOT" \
    "$MODE" \
    "$LOG_FILE"

run_selected_mode
summary

if [ "$FAIL_COUNT" -eq 0 ]; then
    exit 0
fi

exit 1

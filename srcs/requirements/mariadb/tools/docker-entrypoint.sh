#!/bin/sh
set -eu

DATA_DIR="/var/lib/mysql"
SOCKET="/run/mysqld/mysqld.sock"
PID_FILE="/run/mysqld/mariadbd.pid"
SQL_TEMPLATE="/usr/local/share/mariadb/init.sql.template"

ROOT_PASSWORD_FILE="/run/secrets/db_root_password"
USER_PASSWORD_FILE="/run/secrets/db_password"

temp_pid=""
rendered_sql=""

fail()
{
	echo "MariaDB entrypoint error: $1" >&2
	exit 1
}

cleanup()
{
	if [ -n "$rendered_sql" ]; then
		rm -f "$rendered_sql"
	fi

	if [ -n "$temp_pid" ] && kill -0 "$temp_pid" 2>/dev/null; then
		kill "$temp_pid" 2>/dev/null || true
		wait "$temp_pid" 2>/dev/null || true
	fi
}

require_variable()
{
	eval "value=\${$1:-}"
	[ -n "$value" ] || fail "$1 is not set"
}

require_file()
{
	[ -r "$1" ] || fail "cannot read file: $1"
}

validate_identifier()
{
	printf '%s' "$1" | grep -Eq '^[A-Za-z0-9_]+$' \
		|| fail "invalid identifier: $1"
}

sql_escape()
{
	printf '%s' "$1" \
		| sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

wait_for_mariadb()
{
	attempt=0

	until mariadb-admin \
		--protocol=socket \
		--socket="$SOCKET" \
		--user=root \
		ping \
		--silent
	do
		attempt=$((attempt + 1))

		if [ "$attempt" -ge 30 ]; then
			fail "temporary MariaDB server did not become ready"
		fi

		sleep 1
	done
}

initialize_database()
{
	echo "Initializing MariaDB data directory..."

	mariadb-install-db \
		--user=mysql \
		--datadir="$DATA_DIR" \
		--auth-root-authentication-method=normal \
		--skip-test-db

	mariadbd \
		--user=mysql \
		--datadir="$DATA_DIR" \
		--skip-networking \
		--socket="$SOCKET" \
		--pid-file="$PID_FILE" &

	temp_pid=$!

	wait_for_mariadb
	render_initialization_sql

	mariadb \
		--protocol=socket \
		--socket="$SOCKET" \
		--user=root < "$rendered_sql"

	wait "$temp_pid"
	temp_pid=""

	rm -f "$rendered_sql"
	rendered_sql=""

	echo "MariaDB initialization completed."
}

render_initialization_sql()
{
	MYSQL_ROOT_PASSWORD_SQL="$(sql_escape "$MYSQL_ROOT_PASSWORD")"
	MYSQL_PASSWORD_SQL="$(sql_escape "$MYSQL_PASSWORD")"

	export MYSQL_DATABASE
	export MYSQL_USER
	export MYSQL_ROOT_PASSWORD_SQL
	export MYSQL_PASSWORD_SQL

	rendered_sql="$(mktemp /tmp/mariadb-init.XXXXXX.sql)"

	envsubst \
		'${MYSQL_DATABASE}
		${MYSQL_USER}
		${MYSQL_ROOT_PASSWORD_SQL}
		${MYSQL_PASSWORD_SQL}' \
		< "$SQL_TEMPLATE" \
		> "$rendered_sql"

	unset MYSQL_ROOT_PASSWORD_SQL
	unset MYSQL_PASSWORD_SQL
}

trap cleanup EXIT INT TERM

require_variable MYSQL_DATABASE
require_variable MYSQL_USER

validate_identifier "$MYSQL_DATABASE"
validate_identifier "$MYSQL_USER"

require_file "$ROOT_PASSWORD_FILE"
require_file "$USER_PASSWORD_FILE"
require_file "$SQL_TEMPLATE"

MYSQL_ROOT_PASSWORD="$(tr -d '\r\n' < "$ROOT_PASSWORD_FILE")"
MYSQL_PASSWORD="$(tr -d '\r\n' < "$USER_PASSWORD_FILE")"

[ -n "$MYSQL_ROOT_PASSWORD" ] || fail "root password is empty"
[ -n "$MYSQL_PASSWORD" ] || fail "user password is empty"

umask 077

mkdir -p /run/mysqld "$DATA_DIR"
chown -R mysql:mysql /run/mysqld "$DATA_DIR"

if [ ! -d "$DATA_DIR/mysql" ]; then
	initialize_database
fi

unset MYSQL_ROOT_PASSWORD
unset MYSQL_PASSWORD

trap - EXIT INT TERM

exec "$@"

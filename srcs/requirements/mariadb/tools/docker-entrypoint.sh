#!/bin/sh
set -eu

DATA_DIR="/var/lib/mysql"
INIT_MARKER="$DATA_DIR/.inception_initialized"
SQL_TEMPLATE="/usr/local/share/mariadb/init.sql.template"

ROOT_PASSWORD_FILE="/run/secrets/db_root_password"
USER_PASSWORD_FILE="/run/secrets/db_password"

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

render_initialization_sql()
{
	MYSQL_ROOT_PASSWORD_SQL="$(sql_escape "$MYSQL_ROOT_PASSWORD")"
	MYSQL_PASSWORD_SQL="$(sql_escape "$MYSQL_PASSWORD")"
	MARIADB_HOSTNAME_SQL="$(sql_escape "$(hostname)")"

	export MYSQL_DATABASE
	export MYSQL_USER
	export MYSQL_ROOT_PASSWORD_SQL
	export MYSQL_PASSWORD_SQL
	export MARIADB_HOSTNAME_SQL

	rendered_sql="$(mktemp /tmp/mariadb-init.XXXXXX.sql)"

	envsubst \
		'${MYSQL_DATABASE}
		${MYSQL_USER}
		${MYSQL_ROOT_PASSWORD_SQL}
		${MYSQL_PASSWORD_SQL}
		${MARIADB_HOSTNAME_SQL}' \
		< "$SQL_TEMPLATE" \
		> "$rendered_sql"

	unset MYSQL_ROOT_PASSWORD_SQL
	unset MYSQL_PASSWORD_SQL
	unset MARIADB_HOSTNAME_SQL
}

initialize_system_tables()
{
	echo "Initializing MariaDB system tables..."

	rm -f "$INIT_MARKER"

	mariadb-install-db \
		--user=mysql \
		--datadir="$DATA_DIR" \
		--auth-root-authentication-method=normal \
		--skip-test-db
}

run_bootstrap_sql()
{
	mariadbd \
		--bootstrap \
		--user=mysql \
		--datadir="$DATA_DIR" \
		--skip-networking \
		< "$rendered_sql"
}

configure_inception_database()
{
	echo "Configuring the Inception database..."

	render_initialization_sql
	run_bootstrap_sql

	rm -f "$rendered_sql"
	rendered_sql=""

	touch "$INIT_MARKER"
	chown mysql:mysql "$INIT_MARKER"
	chmod 600 "$INIT_MARKER"

	echo "MariaDB initialization completed."
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
	initialize_system_tables
fi

if [ ! -f "$INIT_MARKER" ]; then
	configure_inception_database
fi

unset MYSQL_ROOT_PASSWORD
unset MYSQL_PASSWORD

trap - EXIT INT TERM

exec "$@"

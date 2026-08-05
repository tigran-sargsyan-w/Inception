#!/bin/sh

set -eu

WORDPRESS_DIR="/var/www/html"

DB_PASSWORD_FILE="/run/secrets/db_password"
ADMIN_PASSWORD_FILE="/run/secrets/wp_admin_password"
USER_PASSWORD_FILE="/run/secrets/wp_user_password"
REDIS_PASSWORD_FILE="/run/secrets/redis_password"

fail()
{
	echo "WordPress entrypoint error: $1" >&2
	exit 1
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

run_wp()
{
	runuser -u www-data -- \
		wp --path="$WORDPRESS_DIR" "$@"
}

wait_for_mariadb()
{
	attempt=0

	echo "Waiting for MariaDB..."

	until MYSQL_PWD="$MYSQL_PASSWORD" mariadb \
		--protocol=tcp \
		--host="$MYSQL_HOST" \
		--port="$MARIADB_PORT" \
		--user="$MYSQL_USER" \
		--database="$MYSQL_DATABASE" \
		--execute="SELECT 1" >/dev/null 2>&1
	do
		attempt=$((attempt + 1))

		if [ "$attempt" -ge 30 ]; then
			fail "MariaDB did not become ready"
		fi

		sleep 1
	done

	echo "MariaDB is ready."
}

wait_for_redis()
{
	attempt=0

	echo "Waiting for Redis..."

	until REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli \
		-h="$REDIS_HOST" \
		-p="$REDIS_PORT" \
		ping | grep -q "^PONG$"
	do
		attempt=$((attempt + 1))

		if [ "$attempt" -ge 30 ]; then
			fail "Redis did not become ready"
		fi

		sleep 1
	done

	echo "Redis is ready."
}

download_wordpress()
{
	if [ ! -f "$WORDPRESS_DIR/wp-load.php" ]; then
		echo "Downloading WordPress..."

		run_wp core download

		echo "WordPress downloaded."
	else
		echo "WordPress files already exist."
	fi
}

create_wordpress_config()
{
	if [ ! -f "$WORDPRESS_DIR/wp-config.php" ]; then
		echo "Creating wp-config.php..."

		run_wp config create \
			--dbname="$MYSQL_DATABASE" \
			--dbuser="$MYSQL_USER" \
			--dbpass="$MYSQL_PASSWORD" \
			--dbhost="$MYSQL_HOST:$MARIADB_PORT"

		echo "wp-config.php created."
	fi
}

configure_redis()
{
	echo "Configuring WordPress Redis connection..."

	run_wp config set \
		WP_REDIS_HOST \
		"$REDIS_HOST" \
		--type=constant

	run_wp config set \
		WP_REDIS_PORT \
		"$REDIS_PORT" \
		--type=constant \
		--raw

	run_wp config set \
		WP_REDIS_PASSWORD \
		"trim(file_get_contents('$REDIS_PASSWORD_FILE'))" \
		--type=constant \
		--raw

	echo "WordPress Redis connection configured."
}

install_wordpress()
{
	if ! run_wp core is-installed >/dev/null 2>&1; then
		echo "Installing WordPress..."

		run_wp core install \
			--url="https://$DOMAIN_NAME" \
			--title="$WP_TITLE" \
			--admin_user="$WP_ADMIN_USER" \
			--admin_password="$WP_ADMIN_PASSWORD" \
			--admin_email="$WP_ADMIN_EMAIL" \
			--skip-email

		echo "WordPress installed."
	else
		echo "WordPress is already installed."
	fi
}

install_redis_plugin()
{
	if ! run_wp plugin is-installed redis-cache; then
		echo "Installing Redis Object Cache plugin..."

		run_wp plugin install redis-cache --activate

		echo "Redis Object Cache plugin installed."
	else
		run_wp plugin activate redis-cache >/dev/null 2>&1 || true

		echo "Redis Object Cache plugin already exists."
	fi
}

enable_redis_cache()
{
	echo "Enabling Redis object cache..."

	run_wp redis enable

	echo "Redis object cache enabled."
}

create_second_user()
{
	if ! run_wp user get "$WP_USER" >/dev/null 2>&1; then
		echo "Creating the second WordPress user..."

		run_wp user create \
			"$WP_USER" \
			"$WP_USER_EMAIL" \
			--user_pass="$WP_USER_PASSWORD" \
			--role=author

		echo "Second WordPress user created."
	else
		echo "Second WordPress user already exists."
	fi
}

validate_admin_username()
{
	admin_name="$(printf '%s' "$WP_ADMIN_USER" \
		| tr '[:upper:]' '[:lower:]')"

	case "$admin_name" in
		*admin*)
			fail "WP_ADMIN_USER must not contain admin"
			;;
	esac
}

require_variable DOMAIN_NAME
require_variable MYSQL_HOST
require_variable MYSQL_DATABASE
require_variable MYSQL_USER
require_variable MARIADB_PORT
require_variable WP_TITLE
require_variable WP_ADMIN_USER
require_variable WP_ADMIN_EMAIL
require_variable WP_USER
require_variable WP_USER_EMAIL
require_variable REDIS_HOST
require_variable REDIS_PORT

require_file "$DB_PASSWORD_FILE"
require_file "$ADMIN_PASSWORD_FILE"
require_file "$USER_PASSWORD_FILE"
require_file "$REDIS_PASSWORD_FILE"

MYSQL_PASSWORD="$(tr -d '\r\n' < "$DB_PASSWORD_FILE")"
WP_ADMIN_PASSWORD="$(tr -d '\r\n' < "$ADMIN_PASSWORD_FILE")"
WP_USER_PASSWORD="$(tr -d '\r\n' < "$USER_PASSWORD_FILE")"
REDIS_PASSWORD="$(tr -d '\r\n' < "$REDIS_PASSWORD_FILE")"

[ -n "$MYSQL_PASSWORD" ] || fail "database password is empty"
[ -n "$WP_ADMIN_PASSWORD" ] || fail "administrator password is empty"
[ -n "$WP_USER_PASSWORD" ] || fail "second user password is empty"
[ -n "$REDIS_PASSWORD" ] || fail "Redis password is empty"

validate_admin_username

mkdir -p "$WORDPRESS_DIR"
chown www-data:www-data "$WORDPRESS_DIR"

download_wordpress
wait_for_mariadb
wait_for_redis
create_wordpress_config
install_wordpress
create_second_user
configure_redis
install_redis_plugin
enable_redis_cache

unset MYSQL_PASSWORD
unset WP_ADMIN_PASSWORD
unset WP_USER_PASSWORD
unset REDIS_PASSWORD

exec "$@"
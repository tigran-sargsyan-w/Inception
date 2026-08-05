#!/bin/sh

set -eu

REDIS_PASSWORD_FILE="/run/secrets/redis_password"
REDIS_CONFIG_SOURCE="/etc/redis/redis.conf"
REDIS_CONFIG_RUNTIME="/run/redis/redis.conf"

fail()
{
	echo "Redis entrypoint error: $1" >&2
	exit 1
}

[ -r "$REDIS_PASSWORD_FILE" ] \
	|| fail "cannot read Redis password secret"

[ -r "$REDIS_CONFIG_SOURCE" ] \
	|| fail "cannot read Redis configuration"

REDIS_PASSWORD="$(tr -d '\r\n' < "$REDIS_PASSWORD_FILE")"

[ -n "$REDIS_PASSWORD" ] \
	|| fail "Redis password is empty"

mkdir -p /run/redis

cp "$REDIS_CONFIG_SOURCE" "$REDIS_CONFIG_RUNTIME"

printf '\nrequirepass "%s"\n' \
	"$REDIS_PASSWORD" >> "$REDIS_CONFIG_RUNTIME"

chmod 600 "$REDIS_CONFIG_RUNTIME"

unset REDIS_PASSWORD

exec "$@"
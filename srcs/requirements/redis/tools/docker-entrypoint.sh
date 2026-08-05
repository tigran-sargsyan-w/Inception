#!/bin/sh

set -eu

REDIS_PASSWORD_FILE="/run/secrets/redis_password"
REDIS_CONFIG_FILE="/run/redis/redis.conf"

fail()
{
	echo "Redis entrypoint error: $1" >&2
	exit 1
}

[ -r "$REDIS_PASSWORD_FILE" ] \
	|| fail "cannot read Redis password secret"

REDIS_PASSWORD="$(tr -d '\r\n' < "$REDIS_PASSWORD_FILE")"

[ -n "$REDIS_PASSWORD" ] \
	|| fail "Redis password is empty"

mkdir -p /run/redis

cat > "$REDIS_CONFIG_FILE" <<EOF
bind 0.0.0.0
protected-mode yes
port 6379
daemonize no
supervised no
save ""
appendonly no
requirepass "$REDIS_PASSWORD"
EOF

chmod 600 "$REDIS_CONFIG_FILE"

unset REDIS_PASSWORD

exec "$@"
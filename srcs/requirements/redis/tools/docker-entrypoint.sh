#!/bin/sh

set -eu

REDIS_CONFIG_FILE="/etc/redis/redis.conf"

if [ ! -s "$REDIS_CONFIG_FILE" ]; then
	echo "Redis entrypoint error: file is missing or empty: $REDIS_CONFIG_FILE" >&2
	exit 1
fi

exec "$@"
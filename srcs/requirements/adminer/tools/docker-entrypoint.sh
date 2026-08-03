#!/bin/sh

set -eu

ADMINER_FILE="/var/www/adminer/index.php"

if [ ! -s "$ADMINER_FILE" ]; then
	echo "Adminer entrypoint error: file is missing or empty: $ADMINER_FILE" >&2
	exit 1
fi

exec "$@"
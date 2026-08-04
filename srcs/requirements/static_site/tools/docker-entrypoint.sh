#!/bin/sh

set -eu

STATIC_ROOT="/var/www/static"
INDEX_FILE="$STATIC_ROOT/index.html"

fail()
{
	echo "Static site entrypoint error: $1" >&2
	exit 1
}

[ -d "$STATIC_ROOT" ] \
	|| fail "website directory does not exist: $STATIC_ROOT"

[ -s "$INDEX_FILE" ] \
	|| fail "index file is missing or empty: $INDEX_FILE"

[ -r "$INDEX_FILE" ] \
	|| fail "index file is not readable: $INDEX_FILE"

exec "$@"
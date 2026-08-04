#!/bin/sh

set -eu

CONFIG_FILE="/etc/static-site/server.conf"

fail()
{
	echo "Static site entrypoint error: $1" >&2
	exit 1
}

require_file()
{
	[ -r "$1" ] || fail "cannot read file: $1"
}

require_variable()
{
	eval "value=\${$1:-}"
	[ -n "$value" ] || fail "$1 is not set"
}

load_configuration()
{
	require_file "$CONFIG_FILE"

	. "$CONFIG_FILE"

	require_variable STATIC_SITE_HOST
	require_variable STATIC_SITE_PORT
	require_variable STATIC_SITE_ROOT
}

validate_configuration()
{
	case "$STATIC_SITE_PORT" in
		*[!0-9]* | "")
			fail "STATIC_SITE_PORT must be a number"
			;;
	esac

	[ "$STATIC_SITE_PORT" -ge 1 ] \
		&& [ "$STATIC_SITE_PORT" -le 65535 ] \
		|| fail "STATIC_SITE_PORT must be between 1 and 65535"

	[ -d "$STATIC_SITE_ROOT" ] \
		|| fail "website directory does not exist: $STATIC_SITE_ROOT"

	[ -s "$STATIC_SITE_ROOT/index.html" ] \
		|| fail "index file is missing or empty"
}

run_server()
{
	exec python3 \
		-m http.server \
		"$STATIC_SITE_PORT" \
		--bind "$STATIC_SITE_HOST" \
		--directory "$STATIC_SITE_ROOT"
}

main()
{
	load_configuration
	validate_configuration

	if [ "${1:-}" = "serve" ]; then
		run_server
	fi

	exec "$@"
}

main "$@"
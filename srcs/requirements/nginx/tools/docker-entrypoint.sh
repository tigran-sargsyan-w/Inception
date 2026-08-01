#!/bin/sh

set -eu

TEMPLATE_FILE="/etc/nginx/templates/default.conf.template"
CONFIG_FILE="/etc/nginx/conf.d/default.conf"

CERTIFICATE_FILE="/etc/nginx/ssl/inception.crt"
PRIVATE_KEY_FILE="/etc/nginx/ssl/inception.key"

fail()
{
	echo "NGINX entrypoint error: $1" >&2
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

require_variable DOMAIN_NAME

require_file "$TEMPLATE_FILE"
require_file "$CERTIFICATE_FILE"
require_file "$PRIVATE_KEY_FILE"

envsubst '${DOMAIN_NAME}' \
	< "$TEMPLATE_FILE" \
	> "$CONFIG_FILE"

nginx -t

exec "$@"
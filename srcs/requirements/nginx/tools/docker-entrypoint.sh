#!/bin/sh

set -eu

TEMPLATE_FILE="/etc/nginx/templates/default.conf.template"
CONFIG_FILE="/etc/nginx/conf.d/default.conf"

CERTIFICATE_FILE="/etc/nginx/ssl/inception.crt"
PRIVATE_KEY_FILE="/etc/nginx/ssl/inception.key"

: "${DOMAIN_NAME:?DOMAIN_NAME is not set}"

[ -r "$TEMPLATE_FILE" ] || {
	echo "NGINX template is not readable: $TEMPLATE_FILE" >&2
	exit 1
}

[ -r "$CERTIFICATE_FILE" ] || {
	echo "TLS certificate is not readable: $CERTIFICATE_FILE" >&2
	exit 1
}

[ -r "$PRIVATE_KEY_FILE" ] || {
	echo "TLS private key is not readable: $PRIVATE_KEY_FILE" >&2
	exit 1
}

envsubst '${DOMAIN_NAME}' \
	< "$TEMPLATE_FILE" \
	> "$CONFIG_FILE"

nginx -t

exec "$@"
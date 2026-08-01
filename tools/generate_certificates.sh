#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$ROOT_DIR/srcs/.env"
CERTIFICATE_DIR="$ROOT_DIR/certificates"

CERTIFICATE_FILE="$CERTIFICATE_DIR/inception.crt"
PRIVATE_KEY_FILE="$CERTIFICATE_DIR/inception.key"

fail()
{
	echo "Certificate generation error: $1" >&2
	exit 1
}

command -v openssl >/dev/null 2>&1 \
	|| fail "openssl is not installed"

[ -r "$ENV_FILE" ] \
	|| fail "cannot read environment file: $ENV_FILE"

DOMAIN_NAME="$(sed -n 's/^DOMAIN_NAME=//p' "$ENV_FILE" \
	| tail -n 1 \
	| tr -d '\r')"

[ -n "$DOMAIN_NAME" ] \
	|| fail "DOMAIN_NAME is not set in $ENV_FILE"

case "$DOMAIN_NAME" in
	*[!A-Za-z0-9.-]*)
		fail "DOMAIN_NAME contains invalid characters"
		;;
esac

mkdir -p "$CERTIFICATE_DIR"

if [ -s "$CERTIFICATE_FILE" ] \
	&& [ -s "$PRIVATE_KEY_FILE" ]; then
	echo "TLS certificate already exists."
	exit 0
fi

rm -f "$CERTIFICATE_FILE" "$PRIVATE_KEY_FILE"

echo "Generating TLS certificate for $DOMAIN_NAME..."

openssl req \
	-x509 \
	-nodes \
	-days 365 \
	-newkey rsa:2048 \
	-keyout "$PRIVATE_KEY_FILE" \
	-out "$CERTIFICATE_FILE" \
	-subj "/C=FR/ST=Rhone/L=Lyon/O=42/OU=Inception/CN=$DOMAIN_NAME" \
	-addext "subjectAltName=DNS:$DOMAIN_NAME"

chmod 600 "$PRIVATE_KEY_FILE"
chmod 644 "$CERTIFICATE_FILE"

echo "TLS certificate generated."
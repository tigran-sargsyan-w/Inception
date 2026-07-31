#!/bin/sh

set -eu

CERTIFICATE_DIR="/etc/nginx/ssl"
CERTIFICATE_FILE="$CERTIFICATE_DIR/inception.crt"
PRIVATE_KEY_FILE="$CERTIFICATE_DIR/inception.key"

: "${DOMAIN_NAME:?DOMAIN_NAME is not set}"

mkdir -p "$CERTIFICATE_DIR"

if [ ! -f "$CERTIFICATE_FILE" ] || [ ! -f "$PRIVATE_KEY_FILE" ]; then
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
fi

exec "$@"
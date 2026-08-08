#!/bin/sh

set -eu

FTP_PASSWORD_FILE="/run/secrets/ftp_password"
FTP_ROOT="/var/www/html"

PROFTPD_TEMPLATE="/etc/proftpd/proftpd.conf.template"
PROFTPD_CONFIG="/etc/proftpd/proftpd.conf"

if [ -z "${FTP_USER:-}" ]; then
    echo "Error: FTP_USER is not set." >&2
    exit 1
fi

if [ -z "${FTP_PORT:-}" ]; then
    echo "Error: FTP_PORT is not set." >&2
    exit 1
fi

if [ -z "${FTP_PASV_ADDRESS:-}" ]; then
    echo "Error: FTP_PASV_ADDRESS is not set." >&2
    exit 1
fi

if [ -z "${FTP_PASV_MIN_PORT:-}" ]; then
    echo "Error: FTP_PASV_MIN_PORT is not set." >&2
    exit 1
fi

if [ -z "${FTP_PASV_MAX_PORT:-}" ]; then
    echo "Error: FTP_PASV_MAX_PORT is not set." >&2
    exit 1
fi

if [ ! -s "$FTP_PASSWORD_FILE" ]; then
    echo "Error: FTP password secret is missing or empty." >&2
    exit 1
fi

if ! id "$FTP_USER" >/dev/null 2>&1; then
    if ! id www-data >/dev/null 2>&1; then
        echo "Error: neither $FTP_USER nor www-data exists." >&2
        exit 1
    fi

    groupmod -n "$FTP_USER" www-data

    usermod \
        -l "$FTP_USER" \
        -d "$FTP_ROOT" \
        -s /bin/sh \
        www-data
fi

FTP_PASSWORD="$(cat "$FTP_PASSWORD_FILE")"

printf '%s:%s\n' "$FTP_USER" "$FTP_PASSWORD" | chpasswd

unset FTP_PASSWORD

chown "$FTP_USER:$FTP_USER" "$FTP_ROOT"

sed \
    -e "s|__FTP_PORT__|$FTP_PORT|g" \
    -e "s|__FTP_PASV_ADDRESS__|$FTP_PASV_ADDRESS|g" \
    -e "s|__FTP_PASV_MIN_PORT__|$FTP_PASV_MIN_PORT|g" \
    -e "s|__FTP_PASV_MAX_PORT__|$FTP_PASV_MAX_PORT|g" \
    "$PROFTPD_TEMPLATE" > "$PROFTPD_CONFIG"

exec "$@"
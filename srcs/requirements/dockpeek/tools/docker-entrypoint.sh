#!/bin/sh

set -eu

PASSWORD_FILE="/run/secrets/dockpeek_password"
SECRET_KEY_FILE="/run/secrets/dockpeek_secret_key"

fail()
{
	echo "Dockpeek entrypoint error: $1" >&2
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

require_variable USERNAME

require_file "$PASSWORD_FILE"
require_file "$SECRET_KEY_FILE"

PASSWORD="$(tr -d '\r\n' < "$PASSWORD_FILE")"
SECRET_KEY="$(tr -d '\r\n' < "$SECRET_KEY_FILE")"

[ -n "$PASSWORD" ] || fail "password is empty"
[ -n "$SECRET_KEY" ] || fail "secret key is empty"

export PASSWORD
export SECRET_KEY

exec "$@"
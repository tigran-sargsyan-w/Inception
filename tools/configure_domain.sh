#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$PROJECT_ROOT/srcs/.env"
HOSTS_FILE="/etc/hosts"
HOST_IP="127.0.0.1"


fail()
{
	echo "Domain configuration error: $1" >&2
	exit 1
}


read_domain_name()
{
	[ -r "$ENV_FILE" ] \
		|| fail "cannot read environment file: $ENV_FILE"

	DOMAIN_NAME="$(
		sed -n \
			's/^[[:space:]]*DOMAIN_NAME[[:space:]]*=[[:space:]]*//p' \
			"$ENV_FILE" \
			| tail -n 1 \
			| tr -d '\r'
	)"

	[ -n "$DOMAIN_NAME" ] \
		|| fail "DOMAIN_NAME is not set in $ENV_FILE"

	case "$DOMAIN_NAME" in
		*[!A-Za-z0-9.-]*)
			fail "DOMAIN_NAME contains invalid characters"
			;;
	esac
}


get_domain_mappings()
{
	awk -v domain="$DOMAIN_NAME" '
	{
		line = $0

		sub(/[[:space:]]*#.*/, "", line)
		gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)

		if (line == "")
			next

		count = split(line, fields, /[[:space:]]+/)

		for (index = 2; index <= count; index++)
		{
			if (fields[index] == domain)
				print fields[1]
		}
	}
	' "$HOSTS_FILE"
}


append_domain_mapping()
{
	if [ "$(id -u)" -eq 0 ]; then
		printf '\n%s\t%s\t# Inception\n' \
			"$HOST_IP" \
			"$DOMAIN_NAME" \
			>> "$HOSTS_FILE"
	else
		command -v sudo >/dev/null 2>&1 \
			|| fail "sudo is required to modify $HOSTS_FILE"

		printf '\n%s\t%s\t# Inception\n' \
			"$HOST_IP" \
			"$DOMAIN_NAME" \
			| sudo tee -a "$HOSTS_FILE" >/dev/null
	fi
}


main()
{
	[ -r "$HOSTS_FILE" ] \
		|| fail "cannot read hosts file: $HOSTS_FILE"

	read_domain_name

	echo
	echo "Preparing local domain configuration..."

	mapped_ips="$(get_domain_mappings)"

	if [ -n "$mapped_ips" ]; then
		conflicting_ip="$(
			printf '%s\n' "$mapped_ips" \
				| awk -v expected="$HOST_IP" \
					'$0 != expected { print; exit }'
		)"

		if [ -z "$conflicting_ip" ]; then
			echo "$DOMAIN_NAME already points to $HOST_IP."
			echo
			exit 0
		fi

		echo "Existing mappings for $DOMAIN_NAME:" >&2
		printf '%s\n' "$mapped_ips" >&2

		fail "$DOMAIN_NAME already points to another IP address"
	fi

	echo "Adding $DOMAIN_NAME -> $HOST_IP to $HOSTS_FILE..."

	append_domain_mapping

	echo "Local domain configured successfully."
	echo
}


main "$@"
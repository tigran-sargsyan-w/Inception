#!/bin/sh

set -eu


SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ENV_FILE="$PROJECT_ROOT/srcs/.env"
HOSTS_FILE="/etc/hosts"

HOST_IP="127.0.0.1"


if [ -t 1 ] && [ -z "${NO_COLOR+x}" ]; then
	RESET="\033[0m"
	BOLD="\033[1m"

	GREEN="\033[32m"
	YELLOW="\033[33m"
	RED="\033[31m"
	CYAN="\033[36m"
else
	RESET=""
	BOLD=""

	GREEN=""
	YELLOW=""
	RED=""
	CYAN=""
fi


print_success()
{
	printf "%b✅ %s%b\n" "$GREEN" "$1" "$RESET"
}


print_info()
{
	printf "%bℹ️  %s%b\n" "$CYAN" "$1" "$RESET"
}


print_warning()
{
	printf "%b⚠️  %s%b\n" "$YELLOW" "$1" "$RESET"
}


print_error()
{
	printf "%b❌ %s%b\n" "$RED" "$1" "$RESET" >&2
}


fail()
{
	print_error "$1"
	exit 1
}


read_domain_name()
{
	[ -r "$ENV_FILE" ] \
		|| fail "Cannot read environment file: $ENV_FILE"

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

		field_count = split(line, fields, /[[:space:]]+/)

		for (field_index = 2; field_index <= field_count; field_index++)
		{
			if (fields[field_index] == domain)
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

		return
	fi

	command -v sudo >/dev/null 2>&1 \
		|| fail "sudo is required to modify $HOSTS_FILE"

	printf '\n%s\t%s\t# Inception\n' \
		"$HOST_IP" \
		"$DOMAIN_NAME" \
		| sudo tee -a "$HOSTS_FILE" >/dev/null
}


main()
{
	[ -r "$HOSTS_FILE" ] \
		|| fail "Cannot read hosts file: $HOSTS_FILE"

	read_domain_name

	printf "\n"
	print_info "Preparing local domain configuration for the Inception project..."
	printf "\n"

	mapped_ips="$(get_domain_mappings)"

	if [ -n "$mapped_ips" ]; then
		conflicting_ip="$(
			printf '%s\n' "$mapped_ips" \
				| awk -v expected="$HOST_IP" \
					'$0 != expected { print; exit }'
		)"

		if [ -z "$conflicting_ip" ]; then
			print_info "🌐 $DOMAIN_NAME already points to $HOST_IP. Skipping."

			printf "\n"
			print_success "Existing local domain configuration is valid."
			printf "\n"

			exit 0
		fi

		print_warning "Existing mappings were found for $DOMAIN_NAME:"

		printf '%s\n' "$mapped_ips" \
			| while IFS= read -r mapped_ip; do
				print_warning "$DOMAIN_NAME -> $mapped_ip"
			done

		printf "\n"

		fail "$DOMAIN_NAME already points to another IP address"
	fi

	print_info "Adding $DOMAIN_NAME -> $HOST_IP to $HOSTS_FILE..."
	printf "\n"

	append_domain_mapping

	print_success "Added local domain mapping:"
	print_success "$DOMAIN_NAME -> $HOST_IP"

	printf "\n"
	print_success "Local domain was configured successfully."
	printf "\n"

	print_info "Open the website at: https://$DOMAIN_NAME"
	printf "\n"
}


main "$@"
#!/bin/sh

set -eu


SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

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

	ADMINER_DOMAIN="$(
		sed -n \
			's/^[[:space:]]*ADMINER_DOMAIN[[:space:]]*=[[:space:]]*//p' \
			"$ENV_FILE" \
			| tail -n 1 \
			| tr -d '\r'
	)"

	STATIC_SITE_DOMAIN="$(
		sed -n \
			's/^[[:space:]]*STATIC_SITE_DOMAIN[[:space:]]*=[[:space:]]*//p' \
			"$ENV_FILE" \
			| tail -n 1 \
			| tr -d '\r'
	)"

	DOCKPEEK_DOMAIN="$(
		sed -n \
			's/^[[:space:]]*DOCKPEEK_DOMAIN[[:space:]]*=[[:space:]]*//p' \
			"$ENV_FILE" \
			| tail -n 1 \
			| tr -d '\r'
	)"

	[ -n "$DOMAIN_NAME" ] \
		|| fail "DOMAIN_NAME is not set in $ENV_FILE"

	[ -n "$ADMINER_DOMAIN" ] \
		|| fail "ADMINER_DOMAIN is not set in $ENV_FILE"

	[ -n "$STATIC_SITE_DOMAIN" ] \
		|| fail "STATIC_SITE_DOMAIN is not set in $ENV_FILE"

	[ -n "$DOCKPEEK_DOMAIN" ] \
		|| fail "DOCKPEEK_DOMAIN is not set in $ENV_FILE"

	case "$DOMAIN_NAME" in
		*[!A-Za-z0-9.-]*)
			fail "DOMAIN_NAME contains invalid characters"
			;;
	esac

	case "$ADMINER_DOMAIN" in
		*[!A-Za-z0-9.-]*)
			fail "ADMINER_DOMAIN contains invalid characters"
			;;
	esac

	case "$STATIC_SITE_DOMAIN" in
		*[!A-Za-z0-9.-]*)
			fail "STATIC_SITE_DOMAIN contains invalid characters"
			;;
	esac

	case "$DOCKPEEK_DOMAIN" in
		*[!A-Za-z0-9.-]*)
			fail "DOCKPEEK_DOMAIN contains invalid characters"
			;;
	esac
}


get_domain_mappings()
{
	domain="$1"

	awk -v domain="$domain" '
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
	domain="$1"

	if [ "$(id -u)" -eq 0 ]; then
		printf '\n%s\t%s\t# Inception\n' \
			"$HOST_IP" \
			"$domain" \
			>> "$HOSTS_FILE"

		return
	fi

	command -v sudo >/dev/null 2>&1 \
		|| fail "sudo is required to modify $HOSTS_FILE"

	printf '\n%s\t%s\t# Inception\n' \
		"$HOST_IP" \
		"$domain" \
		| sudo tee -a "$HOSTS_FILE" >/dev/null
}

configure_domain()
{
	domain="$1"

	mapped_ips="$(get_domain_mappings "$domain")"

	if [ -n "$mapped_ips" ]; then
		conflicting_ip="$(
			printf '%s\n' "$mapped_ips" \
				| awk -v expected="$HOST_IP" \
					'$0 != expected { print; exit }'
		)"

		if [ -z "$conflicting_ip" ]; then
			print_info "🌐 $domain already points to $HOST_IP. Skipping."
			return
		fi

		print_warning "Existing mappings were found for $domain:"

		printf '%s\n' "$mapped_ips" \
			| while IFS= read -r mapped_ip; do
				print_warning "$domain -> $mapped_ip"
			done

		fail "$domain already points to another IP address"
	fi

	print_info "Adding $domain -> $HOST_IP to $HOSTS_FILE..."

	append_domain_mapping "$domain"

	print_success "$domain -> $HOST_IP"
}

main()
{
	[ -r "$HOSTS_FILE" ] \
		|| fail "Cannot read hosts file: $HOSTS_FILE"

	read_domain_name

	printf "\n"
	print_info "Preparing local domain configuration for the Inception project..."
	printf "\n"

	configure_domain "$DOMAIN_NAME"
	configure_domain "$ADMINER_DOMAIN"
	configure_domain "$STATIC_SITE_DOMAIN"
	configure_domain "$DOCKPEEK_DOMAIN"

	printf "\n"
	print_success "Local domains were configured successfully."
	printf "\n"

	print_info "WordPress: https://$DOMAIN_NAME"
	print_info "Adminer: https://$ADMINER_DOMAIN"
	print_info "Portfolio: https://$STATIC_SITE_DOMAIN"
	print_info "Dockpeek: https://$DOCKPEEK_DOMAIN"
	printf "\n"
}


main "$@"
#!/bin/sh

set -eu


SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

ENV_FILE="$PROJECT_ROOT/srcs/.env"
CERTIFICATES_DIRECTORY="$PROJECT_ROOT/certificates"

CERTIFICATE_FILE="$CERTIFICATES_DIRECTORY/inception.crt"
PRIVATE_KEY_FILE="$CERTIFICATES_DIRECTORY/inception.key"


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


certificate_is_usable()
{
	certificate_public_key=""
	private_public_key=""

	[ -s "$CERTIFICATE_FILE" ] || return 1
	[ -s "$PRIVATE_KEY_FILE" ] || return 1

	openssl x509 \
		-in "$CERTIFICATE_FILE" \
		-noout \
		-checkend 0 \
		>/dev/null 2>&1 \
		|| return 1

	openssl x509 \
		-in "$CERTIFICATE_FILE" \
		-noout \
		-checkhost "$DOMAIN_NAME" \
		>/dev/null 2>&1 \
		|| return 1

	openssl x509 \
		-in "$CERTIFICATE_FILE" \
		-noout \
		-checkhost "$ADMINER_DOMAIN" \
		>/dev/null 2>&1 \
		|| return 1

	openssl x509 \
		-in "$CERTIFICATE_FILE" \
		-noout \
		-checkhost "$STATIC_SITE_DOMAIN" \
		>/dev/null 2>&1 \
		|| return 1

	openssl x509 \
		-in "$CERTIFICATE_FILE" \
		-noout \
		-checkhost "$DOCKPEEK_DOMAIN" \
		>/dev/null 2>&1 \
		|| return 1

	certificate_public_key="$(
		openssl x509 \
			-in "$CERTIFICATE_FILE" \
			-pubkey \
			-noout \
			2>/dev/null
	)" || return 1

	private_public_key="$(
		openssl pkey \
			-in "$PRIVATE_KEY_FILE" \
			-pubout \
			2>/dev/null
	)" || return 1

	[ "$certificate_public_key" = "$private_public_key" ]
}


read_domain_name()
{
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


generate_certificate()
{
	openssl_output=""

	if ! openssl_output="$(
		openssl req \
			-x509 \
			-nodes \
			-days 365 \
			-newkey rsa:2048 \
			-keyout "$PRIVATE_KEY_FILE" \
			-out "$CERTIFICATE_FILE" \
			-subj \
			"/C=FR/ST=Rhone/L=Lyon/O=42/OU=Inception/CN=$DOMAIN_NAME" \
			-addext "subjectAltName=DNS:$DOMAIN_NAME,DNS:*.$DOMAIN_NAME" \
			2>&1
	)"; then
		rm -f "$CERTIFICATE_FILE" "$PRIVATE_KEY_FILE"

		print_error "OpenSSL failed to generate the TLS certificate."

		if [ -n "$openssl_output" ]; then
			printf "%s\n" "$openssl_output" >&2
		fi

		exit 1
	fi

	chmod 644 "$CERTIFICATE_FILE"
	chmod 600 "$PRIVATE_KEY_FILE"
}


main()
{
	command -v openssl >/dev/null 2>&1 \
		|| fail "openssl is not installed"

	[ -r "$ENV_FILE" ] \
		|| fail "Cannot read environment file: $ENV_FILE"

	read_domain_name

	printf "\n"
	print_info "Preparing TLS certificate for the Inception project..."
	printf "\n"

	mkdir -p "$CERTIFICATES_DIRECTORY"

	if certificate_is_usable; then
		print_info "🔒 TLS certificate already exists for $DOMAIN_NAME. Skipping."

		printf "\n"
		print_info "Existing certificate and private key were kept unchanged."
		printf "\n"

		exit 0
	fi

	if [ -e "$CERTIFICATE_FILE" ] || [ -e "$PRIVATE_KEY_FILE" ]; then
		print_warning "The existing TLS files are incomplete, invalid, expired, or belong to another domain."
		print_warning "The certificate and private key will be recreated."
		printf "\n"
	fi

	rm -f "$CERTIFICATE_FILE" "$PRIVATE_KEY_FILE"

	print_info "Generating a self-signed certificate for $DOMAIN_NAME..."

	generate_certificate

	print_success "Created TLS certificate: certificates/inception.crt"
	print_success "Created private key: certificates/inception.key"

	printf "\n"
	print_success "TLS certificate files were generated successfully."
	printf "\n"

	print_info "Certificate permissions: 644."
	print_info "Private key permissions: 600."
	print_warning "Never add certificates/inception.key to Git."
	printf "\n"
}


main "$@"
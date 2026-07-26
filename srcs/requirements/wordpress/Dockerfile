FROM debian:bookworm

ARG WP_CLI_VERSION=2.12.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        mariadb-client \
        php-cli \
        php-curl \
        php-fpm \
        php-gd \
        php-intl \
        php-mbstring \
        php-mysql \
        php-xml \
        php-zip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
        "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar" \
        -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp \
    && wp --info

RUN mkdir -p \
        /run/php \
        /var/www/html \
        /var/www/.wp-cli/cache \
    && chown -R www-data:www-data \
        /var/www/html \
        /var/www/.wp-cli

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf
COPY tools/wordpress.sh /usr/local/bin/wordpress.sh

RUN chmod +x /usr/local/bin/wordpress.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wordpress.sh"]

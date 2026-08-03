FROM debian:bookworm

ARG ADMINER_VERSION=5.5.1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        php-fpm \
        php-mysql \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/php /var/www/adminer \
    && curl -fsSL \
        "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}-mysql-en.php" \
        -o /var/www/adminer/index.php \
    && test -s /var/www/adminer/index.php \
    && chown -R www-data:www-data /var/www/adminer

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

WORKDIR /var/www/adminer

EXPOSE 9000

CMD ["php-fpm8.2", "-F"]
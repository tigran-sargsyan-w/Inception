FROM debian:bookworm

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

RUN mkdir -p /run/php /var/www/html

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

WORKDIR /var/www/html

EXPOSE 9000

CMD ["php-fpm8.2", "-F"]

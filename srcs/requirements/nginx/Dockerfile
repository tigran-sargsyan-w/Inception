FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        nginx \
        openssl \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

RUN mkdir -p \
        /etc/nginx/ssl \
        /var/www/html

COPY conf/default.conf /etc/nginx/conf.d/default.conf
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && printf '%s\n' \
        '<!doctype html>' \
        '<html>' \
        '<body>' \
        '<h1>NGINX HTTPS works</h1>' \
        '</body>' \
        '</html>' \
        > /var/www/html/index.html

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
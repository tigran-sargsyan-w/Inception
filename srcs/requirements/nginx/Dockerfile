FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gettext-base \
        nginx \
        openssl \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

RUN mkdir -p \
        /etc/nginx/ssl \
        /etc/nginx/templates \
        /var/www/html

COPY conf/default.conf.template \
    /etc/nginx/templates/default.conf.template

COPY tools/docker-entrypoint.sh \
    /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
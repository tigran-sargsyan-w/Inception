FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        nginx \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default

COPY conf/default.conf /etc/nginx/conf.d/default.conf

RUN printf '%s\n' \
        '<!doctype html>' \
        '<html>' \
        '<body>' \
        '<h1>NGINX container works</h1>' \
        '</body>' \
        '</html>' \
        > /var/www/html/index.html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
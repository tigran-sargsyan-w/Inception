FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
        /etc/static-site \
        /var/www/static

COPY conf/server.conf /etc/static-site/server.conf
COPY website/ /var/www/static/
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www/static

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["serve"]
FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/static

COPY website/ /var/www/static/
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["python3", "-m", "http.server", "8080", "--bind", "0.0.0.0", "--directory", "/var/www/static"]
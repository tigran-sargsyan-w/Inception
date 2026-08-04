FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/static

COPY website/ /var/www/static/

EXPOSE 8080

CMD ["python3", "-m", "http.server", "8080", "--bind", "0.0.0.0", "--directory", "/var/www/static"]
FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        redis-server \
        redis-tools \
    && rm -rf /var/lib/apt/lists/*

COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 6379

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["redis-server", "/run/redis/redis.conf"]
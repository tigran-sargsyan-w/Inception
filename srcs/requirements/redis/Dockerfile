FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        redis-server \
        redis-tools \
    && rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/redis.conf

EXPOSE 6379

CMD ["redis-server", "/etc/redis/redis.conf"]
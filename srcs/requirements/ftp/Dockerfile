FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gettext-base \
        passwd \
        proftpd-core \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
        /run/proftpd \
        /var/www/html

COPY conf/proftpd.conf.template /etc/proftpd/proftpd.conf.template
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 21 21000-21010

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/proftpd", "-n", "-c", "/etc/proftpd/proftpd.conf"]
FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        passwd \
        vsftpd \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
        /var/run/vsftpd/empty \
        /var/www/html

COPY conf/vsftpd.conf.template /etc/vsftpd.conf.template
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 21 21000-21010

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/sbin/vsftpd", "/etc/vsftpd.conf"]
FROM debian:bookworm

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		mariadb-server \
		gettext-base \
	&& rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mysql/*

COPY conf/99-inception.cnf /etc/mysql/mariadb.conf.d/99-inception.cnf
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY tools/init.sql.template /usr/local/share/mariadb/init.sql.template

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["mariadbd", "--user=mysql"]

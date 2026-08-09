FROM debian:bookworm

ARG DOCKPEEK_VERSION=v1.7.2

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN curl -fsSL \
        "https://github.com/dockpeek/dockpeek/archive/refs/tags/${DOCKPEEK_VERSION}.tar.gz" \
        | tar -xz --strip-components=1

RUN python3 -m venv /opt/dockpeek-venv \
    && /opt/dockpeek-venv/bin/pip install \
        --no-cache-dir \
        -r requirements.txt

ENV PATH="/opt/dockpeek-venv/bin:${PATH}"
COPY tools/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["gunicorn", "-c", "gunicorn.conf.py", "run:app"]
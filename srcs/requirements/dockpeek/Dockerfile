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

EXPOSE 8000

CMD ["gunicorn", "-c", "gunicorn.conf.py", "run:app"]
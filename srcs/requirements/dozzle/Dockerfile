FROM debian:bookworm AS builder

ARG DOZZLE_VERSION=v10.6.15
ARG NODE_VERSION=25.9.0
ARG GO_VERSION=1.26.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
        "https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-linux-x64.tar.xz" \
        | tar -xJ -C /usr/local --strip-components=1

RUN curl -fsSL \
        "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
        | tar -xz -C /usr/local

ENV PATH="/usr/local/go/bin:${PATH}"
ENV CI=true

RUN corepack enable

WORKDIR /build

RUN git clone \
        --depth 1 \
        --branch "${DOZZLE_VERSION}" \
        https://github.com/amir20/dozzle.git \
        .

RUN pnpm install --frozen-lockfile --ignore-scripts
RUN pnpm build

RUN go mod download

RUN CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    go build \
        -ldflags "-s -w -X github.com/amir20/dozzle/internal/support/cli.Version=${DOZZLE_VERSION}" \
        -o /dozzle

FROM debian:bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /dozzle /usr/local/bin/dozzle

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/dozzle"]
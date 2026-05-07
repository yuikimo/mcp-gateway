ARG GO_IMAGE=golang:1.23-alpine
ARG NODE_IMAGE=node:20-alpine

FROM ${GO_IMAGE} AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go env -w GO111MODULE=on && \
    go env -w GOPROXY=https://goproxy.cn,direct && \
    go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o proxy-server

FROM ${NODE_IMAGE}

ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache git python3 py3-pip && \
    python3 -m pip install --no-cache-dir --prefix=/opt/uv -i "${PIP_INDEX_URL}" uv && \
    ln -sf /opt/uv/bin/uv /usr/local/bin/uv && \
    printf '%s\n' '#!/bin/sh' 'exec /usr/local/bin/uv tool run "$@"' > /usr/local/bin/uvx

# Copy the proxy server binary from builder
COPY --from=builder /app/proxy-server /usr/local/bin/

# Add execute permissions and set root user
USER root
RUN chmod +x /usr/local/bin/proxy-server && \
    chmod +x /usr/local/bin/uvx && \
    chmod +x /usr/local/bin/uv

# Set working directory
WORKDIR /etc/proxy

# Set the proxy server as entrypoint
ENTRYPOINT ["/usr/local/bin/proxy-server"]

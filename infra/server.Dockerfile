FROM node:22-bookworm-slim AS web-builder

WORKDIR /web/client/web

COPY client/web/package*.json ./
RUN npm install

COPY client/web/ ./
RUN npm run build

FROM rust:1.75 AS builder

WORKDIR /app

# Cache dependencies
COPY Cargo.toml .
COPY core/crypto/Cargo.toml core/crypto/Cargo.toml
COPY server/Cargo.toml server/Cargo.toml

RUN mkdir core/crypto/src server/src
RUN echo "fn main() {}" > server/src/main.rs
RUN echo "pub fn dummy() {}" > core/crypto/src/lib.rs
RUN cargo build -p familychat-server --release || true

# Build application
RUN rm -rf core/crypto/src server/src
COPY . .
RUN cargo build -p familychat-server --release

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y ca-certificates openssl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/familychat-server /usr/local/bin/familychat-server
COPY --from=web-builder /web/client/web/dist /var/www/familychat

ENV RUST_LOG=info
ENV WEB_ROOT=/var/www/familychat

EXPOSE 8080

CMD ["familychat-server"]

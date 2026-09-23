# Runtime-only — binary is cross-compiled on your Mac via scripts/build-server.sh before deploy.
# No apt-get: VPS DNS often fails during Podman builds (can't reach deb.debian.org).
FROM docker.io/library/debian:bookworm-slim
# Vendored CA bundle + Dart SDK (health-check scripts)
COPY infra/ssl/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY infra/dart-sdk /opt/dart
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs
ENV PATH="/opt/dart/bin:${PATH}"
WORKDIR /app
COPY apps/server/server /app/server
COPY apps/server/lib/db/migrations /app/lib/db/migrations
COPY apps/dashboard/build/web /app/dashboard/build/web
ENV DASHBOARD_WEB_DIR=/app/dashboard/build/web
EXPOSE 8080
CMD ["/app/server"]

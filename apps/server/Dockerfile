# Runtime-only — binary is cross-compiled on your Mac via scripts/build-server.sh before deploy.
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY apps/server/server /app/server
COPY apps/server/lib/db/migrations /app/lib/db/migrations
COPY apps/dashboard/build/web /app/dashboard/build/web
ENV DASHBOARD_WEB_DIR=/app/dashboard/build/web
EXPOSE 8080
CMD ["/app/server"]

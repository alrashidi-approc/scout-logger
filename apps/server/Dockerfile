# Podman on Hetzner requires fully qualified image names (no implicit docker.io).
FROM docker.io/library/dart:3.10 AS build
WORKDIR /app
COPY packages/scout_models packages/scout_models
COPY apps/server apps/server
WORKDIR /app/apps/server
RUN dart pub get
RUN dart compile exe bin/server.dart -o server

FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/apps/server/server /app/server
COPY apps/server/lib/db/migrations /app/lib/db/migrations
COPY apps/dashboard/build/web /app/dashboard/build/web
ENV DASHBOARD_WEB_DIR=/app/dashboard/build/web
EXPOSE 8080
CMD ["/app/server"]

FROM busybox:1.37 AS base
ARG APP_VERSION=dev
RUN mkdir -p /www && printf 'ok %s\n' "$APP_VERSION" > /www/health

FROM base AS app
EXPOSE 8080
HEALTHCHECK --interval=5s --timeout=3s --retries=3 CMD wget -qO- http://127.0.0.1:8080/health || exit 1
CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]

FROM base AS worker
CMD ["sh", "-c", "trap 'exit 0' TERM; while :; do sleep 1; done"]

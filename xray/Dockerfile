FROM ghcr.io/xtls/xray-core:latest AS xray-core
FROM alpine:3.20

RUN apk add --no-cache python3

COPY --from=xray-core /usr/local/bin/xray /usr/local/bin/xray
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 10443

ENTRYPOINT ["/entrypoint.sh"]

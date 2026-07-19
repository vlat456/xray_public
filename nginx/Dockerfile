FROM nginx:stable-alpine

RUN apk add --no-cache gettext openssl && \
    mkdir -p /etc/nginx/ssl /var/www/html && \
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/privkey.pem \
      -out /etc/nginx/ssl/fullchain.pem \
      -subj "/CN=localhost" 2>/dev/null

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443

ENTRYPOINT ["/entrypoint.sh"]

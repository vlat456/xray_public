#!/bin/sh
set -e

DECOY_DOMAIN=${DECOY_DOMAIN:-example.com}
DECOY_TITLE=${DECOY_TITLE:-Decoy Site}
XRAY_UPSTREAM=${XRAY_UPSTREAM:-xray:10443}
HTTP_PORT=80
HTTPS_PORT=443

if [ "$NGINX_HTTPS_PORT" = "443" ] || [ -z "$NGINX_HTTPS_PORT" ]; then
  REDIRECT_PORT=""
else
  REDIRECT_PORT=":$NGINX_HTTPS_PORT"
fi

mkdir -p /var/www/html
CERT_FILE=/etc/nginx/ssl/fullchain.pem
KEY_FILE=/etc/nginx/ssl/privkey.pem

cat > /etc/nginx/nginx.conf <<EOF
events {
    worker_connections 1024;
}

http {
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    server {
        listen $HTTP_PORT;
        server_name $DECOY_DOMAIN;
        location / { return 301 https://\$host$REDIRECT_PORT\$request_uri; }
    }

    server {
        listen 127.0.0.1:1443 ssl;
        server_name $DECOY_DOMAIN;
        ssl_certificate $CERT_FILE;
        ssl_certificate_key $KEY_FILE;

        root /var/www/html;
        index index.html;
        location / { try_files \$uri \$uri/ =404; }
    }

}

stream {
    resolver 127.0.0.11 valid=10s;

    map \$ssl_preread_server_name \$backend {
        $DECOY_DOMAIN              127.0.0.1:1443;
        default                    $XRAY_UPSTREAM;
    }

    server {
        listen $HTTPS_PORT reuseport;
        ssl_preread on;
        proxy_pass \$backend;
    }
}
EOF

# Generate decoy site if not present
if [ ! -f /var/www/html/index.html ]; then
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$DECOY_TITLE</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
       background: #f5f7fa; color: #333; display: flex; justify-content: center;
       align-items: center; min-height: 100vh; }
.card { background: white; border-radius: 12px; padding: 48px; box-shadow: 0 2px 16px rgba(0,0,0,0.06);
        max-width: 520px; text-align: center; }
h1 { font-size: 28px; font-weight: 600; margin-bottom: 8px; color: #111; }
p { color: #666; line-height: 1.6; }
</style>
</head>
<body>
<div class="card">
  <h1>$DECOY_TITLE</h1>
  <p>IT consulting, digital infrastructure, and managed services.</p>
</div>
</body>
</html>
EOF
fi

echo "[nginx] Config generated. Starting nginx..."
exec nginx -g "daemon off;"

#!/bin/sh
set -e

# Default values (fallback) — set these before running
PUBLIC_KEY=${PUBLIC_KEY:-CHANGE_ME}
SERVER=${SERVER:-CHANGE_ME}
PORT=${PORT:-443}
SERVER_NAME=${SERVER_NAME:-steamcommunity.com}
SHORT_ID=${SHORT_ID:-cbdc51eb}
CONFIG=${CONFIG:-/usr/local/etc/xray/config.json}

UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
EMAIL="${1:-}"
FLOW=xtls-rprx-vision

if [ -f .env ]; then
  echo "[add-user] Dockerized environment detected (.env found)"
  
  # Helper function to safely read env variables without sourcing
  get_env_var() {
    grep "^$1=" .env | sed 's/[[:space:]]*#.*//' | cut -d= -f2- | sed 's/^["\x27]//;s/["\x27]$//' | xargs
  }
  
  XRAY_REALITY_PRIVATE_KEY=$(get_env_var XRAY_REALITY_PRIVATE_KEY)
  DECOY_DOMAIN=$(get_env_var DECOY_DOMAIN)
  NGINX_HTTPS_PORT=$(get_env_var NGINX_HTTPS_PORT)
  XRAY_REALITY_SERVER_NAMES=$(get_env_var XRAY_REALITY_SERVER_NAMES)
  XRAY_REALITY_SHORT_IDS=$(get_env_var XRAY_REALITY_SHORT_IDS)
  
  # Try to get public key using dockerized xray
  if docker compose ps xray >/dev/null 2>&1; then
    PUB_KEY=$(docker compose exec -T xray xray x25519 -i "$XRAY_REALITY_PRIVATE_KEY" | grep "PublicKey" | awk '{print $NF}' | tr -d '\r')
    if [ -n "$PUB_KEY" ]; then
      PUBLIC_KEY="$PUB_KEY"
    fi
  fi
  
  # Use decoy domain as default server address if available
  if [ -n "$DECOY_DOMAIN" ]; then
    SERVER="$DECOY_DOMAIN"
  fi
  
  if [ -n "$NGINX_HTTPS_PORT" ]; then
    PORT="$NGINX_HTTPS_PORT"
  fi
  
  if [ -n "$XRAY_REALITY_SERVER_NAMES" ]; then
    SERVER_NAME=$(echo "$XRAY_REALITY_SERVER_NAMES" | cut -d, -f1)
  fi
  
  if [ -n "$XRAY_REALITY_SHORT_IDS" ]; then
    SHORT_ID=$(echo "$XRAY_REALITY_SHORT_IDS" | cut -d, -f1)
  fi
  
  # Build user entry
  CLIENT_STR="$UUID"
  if [ -n "$EMAIL" ]; then
    CLIENT_STR="$UUID,$EMAIL"
  fi
  
  # Append to XRAY_CLIENTS in .env
  if grep -q "^XRAY_CLIENTS=" .env; then
    current_clients=$(grep "^XRAY_CLIENTS=" .env | cut -d= -f2-)
    if [ -z "$current_clients" ]; then
      new_clients="$CLIENT_STR"
    else
      new_clients="$current_clients;$CLIENT_STR"
    fi
    awk -v val="$new_clients" '/^XRAY_CLIENTS=/{sub(/=.*/, "=" val)}1' .env > .env.tmp && mv .env.tmp .env
  else
    echo "XRAY_CLIENTS=$CLIENT_STR" >> .env
  fi
  
  echo "[add-user] Client added to .env. Restarting xray container..."
  docker compose up -d xray
else
  # Host-based setup
  CLIENT_JSON="{\"id\":\"$UUID\",\"flow\":\"$FLOW\""
  [ -n "$EMAIL" ] && CLIENT_JSON="$CLIENT_JSON,\"email\":\"$EMAIL\""
  CLIENT_JSON="$CLIENT_JSON}"

  python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data["inbounds"][0]["settings"]["clients"].append(json.loads(sys.argv[2]))
with open(sys.argv[1], "w") as f:
    json.dump(data, f, indent=2)
print("OK")
' "$CONFIG" "$CLIENT_JSON"

  systemctl restart xray
fi

VLESS_LINK="vless://${UUID}@${SERVER}:${PORT}?type=tcp&security=reality&flow=${FLOW}&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}"

echo ""
echo "=== New client ==="
echo "UUID:   $UUID"
echo "Email:  ${EMAIL:-client-$(date +%s)}"
echo ""
echo "$VLESS_LINK"
echo ""
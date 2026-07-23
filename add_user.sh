#!/bin/sh
set -e

command -v python3 >/dev/null 2>&1 || { echo "Error: python3 required. Install: apt install python3 (Debian/Ubuntu) or dnf install python3 (RHEL)"; exit 1; }

# Default values (fallback) — set these before running
PUBLIC_KEY=${PUBLIC_KEY:-CHANGE_ME}
SERVER=${SERVER:-CHANGE_ME}
PORT=${PORT:-443}
SERVER_NAME=${SERVER_NAME:-steamcommunity.com}
SHORT_ID=${SHORT_ID:-cbdc51eb}
CONFIG=${CONFIG:-/usr/local/etc/xray/config.json}

UUID=$(uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())")
USERNAME="${1:-}"
FLOW=xtls-rprx-vision
TRANSPORT=tcp

if [ -f .env ]; then
  echo "[add-user] Dockerized environment detected (.env found)"
  
  # Helper function to safely read env variables without sourcing
  get_env_var() {
    python3 -c "
import sys, re
var = sys.argv[1]
with open('.env') as f:
    for line in f:
        line = line.strip()
        if re.match(r'^' + var + '=', line):
            v = line.split('=', 1)[1].strip().strip(\"'\").strip('\"')
            if v:
                print(v)
            break
" "$1"
  }
  
  XRAY_REALITY_PRIVATE_KEY=$(get_env_var XRAY_REALITY_PRIVATE_KEY)
  DECOY_DOMAIN=$(get_env_var DECOY_DOMAIN)
  NGINX_HTTPS_PORT=$(get_env_var NGINX_HTTPS_PORT)
  XRAY_REALITY_SERVER_NAMES=$(get_env_var XRAY_REALITY_SERVER_NAMES)
  XRAY_REALITY_SHORT_IDS=$(get_env_var XRAY_REALITY_SHORT_IDS)
  XRAY_NETWORK=$(get_env_var XRAY_NETWORK)
  if [ "$XRAY_NETWORK" = "xhttp" ]; then
    TRANSPORT=xhttp
    FLOW=
  fi
  
  # Try to get public key using dockerized xray
  PUBLIC_KEY=""
  if docker compose ps --status running xray 2>/dev/null | grep -q "Up"; then
    PUB_KEY=$(docker compose exec -T xray xray x25519 -i "$XRAY_REALITY_PRIVATE_KEY" 2>/dev/null | grep "PublicKey" | awk '{print $NF}' | tr -d '\r')
    if [ -n "$PUB_KEY" ]; then
      PUBLIC_KEY="$PUB_KEY"
    fi
  fi
  if [ -z "$PUBLIC_KEY" ] && command -v xray >/dev/null 2>&1; then
    PUB_KEY=$(xray x25519 -i "$XRAY_REALITY_PRIVATE_KEY" 2>/dev/null | grep "PublicKey" | awk '{print $NF}')
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
    all_ids=$(echo "$XRAY_REALITY_SHORT_IDS" | python3 -c "import sys,random; ids=[x for x in sys.stdin.read().strip().split(',') if x]; print(random.choice(ids) if ids else '')")
    [ -n "$all_ids" ] && SHORT_ID="$all_ids"
  fi
  
  # Build user entry
  CLIENT_STR="$UUID"
  if [ -n "$USERNAME" ]; then
    CLIENT_STR="$UUID,$USERNAME"
  fi
  
  # Append to XRAY_CLIENTS in .env
  if grep -q "^XRAY_CLIENTS=" .env; then
    current_clients=$(grep "^XRAY_CLIENTS=" .env | tail -1 | cut -d= -f2-)
    if [ -z "$current_clients" ] || [ "$current_clients" = "CHANGE_ME" ]; then
      new_clients="$CLIENT_STR"
    else
      new_clients="$current_clients;$CLIENT_STR"
    fi
    awk -v val="$new_clients" '!/^XRAY_CLIENTS=/{print} /^XRAY_CLIENTS=/ && !found{print "XRAY_CLIENTS=" val; found=1}' .env > .env.tmp && mv .env.tmp .env
  else
    echo "XRAY_CLIENTS=$CLIENT_STR" >> .env
  fi
  
  echo "[add-user] Client added to .env. Restarting xray container..."
  docker compose up -d xray
else
  # Host-based setup
  CLIENT_JSON="{\"id\":\"$UUID\",\"flow\":\"$FLOW\""
  [ -n "$USERNAME" ] && CLIENT_JSON="$CLIENT_JSON,\"email\":\"$USERNAME\""
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

FLOW_ARG=""
[ -n "$FLOW" ] && FLOW_ARG="flow=${FLOW}&"
VLESS_LINK="vless://${UUID}@${SERVER}:${PORT}?type=${TRANSPORT}&security=reality&${FLOW_ARG}encryption=none&sni=${SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}${USERNAME:+#${USERNAME}}"

QR_URL=$(python3 -c "import urllib.parse; print('https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=' + urllib.parse.quote('$VLESS_LINK'))")

GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
printf "${BOLD}${GREEN}🎉 New client${NC}\n"
printf "  ${CYAN}🔑${NC} UUID:     ${BOLD}%s${NC}\n" "$UUID"
printf "  ${CYAN}👤${NC} username: ${BOLD}%s${NC}\n" "${USERNAME:-client-$(date +%s)}"
echo ""
printf "  ${CYAN}🔗${NC} VLESS: %s\n" "$VLESS_LINK"
printf "  ${CYAN}📱${NC} QR:    %s\n" "$QR_URL"
echo ""
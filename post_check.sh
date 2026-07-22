#!/bin/sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

pass() { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$*"; fail_count=$((fail_count + 1)); }
header() { printf "\n${BOLD}%s${NC}\n" "$*"; }

fail_count=0

# ──────────────────────────────────────────────────

header "1. System prerequisites"
if command -v python3 >/dev/null 2>&1; then
  pass "python3: $(python3 --version 2>&1)"
else
  fail "python3 not found (install: apt install python3 / dnf install python3)"
fi

if docker --version >/dev/null 2>&1; then
  pass "docker: $(docker --version 2>&1)"
else
  fail "docker not found"
fi

if docker compose version >/dev/null 2>&1; then
  pass "docker compose: $(docker compose version 2>&1)"
else
  fail "docker compose plugin not found"
fi

if [ ! -f .env ]; then
  fail ".env not found. Copy from .env.example"
  header "SKIPPING remaining checks (no .env)"
  exit $fail_count
fi

get_env() {
  python3 -c "
import sys, re
with open('.env') as f:
    for line in f:
        line = line.strip()
        if re.match(r'^' + sys.argv[1] + '=', line):
            v = line.split('=', 1)[1].strip().strip(\"'\").strip('\"')
            if v: print(v)
            break
" "$1" 2>/dev/null
}

PRIVKEY=$(get_env XRAY_REALITY_PRIVATE_KEY)
DEST=$(get_env XRAY_REALITY_DEST)
SERVER_NAMES=$(get_env XRAY_REALITY_SERVER_NAMES)
SHORT_IDS=$(get_env XRAY_REALITY_SHORT_IDS)
DECOY=$(get_env DECOY_DOMAIN)
CLIENTS=$(get_env XRAY_CLIENTS)
HTTP_PORT=$(get_env NGINX_HTTP_PORT)
HTTPS_PORT=$(get_env NGINX_HTTPS_PORT)
SSL_DIR=$(get_env SSL_DIR)

# ──────────────────────────────────────────────────

header "2. .env validation"

if [ -z "$PRIVKEY" ]; then
  fail "XRAY_REALITY_PRIVATE_KEY is empty"
elif [ "$PRIVKEY" = "CHANGE_ME" ]; then
  fail "XRAY_REALITY_PRIVATE_KEY still set to CHANGE_ME (run: docker run --rm --entrypoint xray ghcr.io/xtls/xray-core:latest x25519)"
else
  pass "XRAY_REALITY_PRIVATE_KEY is set"
fi

if echo "$DEST" | grep -qE '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}:[0-9]+$'; then
  pass "XRAY_REALITY_DEST: $DEST"
else
  fail "XRAY_REALITY_DEST format invalid (expected host:port, got: $DEST)"
fi

DEST_HOST=$(echo "$DEST" | cut -d: -f1)
if [ -z "$SERVER_NAMES" ]; then
  warn "XRAY_REALITY_SERVER_NAMES not set — will derive from DEST ($DEST_HOST)"
  SERVER_NAMES="$DEST_HOST"
fi
pass "XRAY_REALITY_SERVER_NAMES: $SERVER_NAMES"

if [ -z "$SHORT_IDS" ]; then
  fail "XRAY_REALITY_SHORT_IDS is empty"
else
  pass "XRAY_REALITY_SHORT_IDS has $(echo "$SHORT_IDS" | tr ',' '\n' | wc -l | tr -d ' ') shortId(s)"
fi

if [ -z "$DECOY" ]; then
  fail "DECOY_DOMAIN is empty"
elif [ "$DECOY" = "example.com" ]; then
  warn "DECOY_DOMAIN still set to example.com — replace with your real domain"
elif echo "$DECOY" | grep -qiE '^(example\.|your-|my-)'; then
  warn "DECOY_DOMAIN looks like a placeholder: $DECOY"
else
  pass "DECOY_DOMAIN: $DECOY"
fi

if [ -z "$CLIENTS" ]; then
  fail "XRAY_CLIENTS is empty"
elif [ "$CLIENTS" = "CHANGE_ME" ]; then
  warn "No clients configured yet. Run: ./add_user.sh <username>"
else
  n_clients=$(echo "$CLIENTS" | tr ';' '\n' | wc -l | tr -d ' ')
  pass "XRAY_CLIENTS: $n_clients client(s) configured"
fi

if echo "$HTTP_PORT" | grep -qE '^[0-9]+$'; then
  pass "NGINX_HTTP_PORT: $HTTP_PORT"
else
  warn "NGINX_HTTP_PORT not set, default 80"
fi

if echo "$HTTPS_PORT" | grep -qE '^[0-9]+$'; then
  pass "NGINX_HTTPS_PORT: $HTTPS_PORT"
else
  warn "NGINX_HTTPS_PORT not set, default 443"
fi

# ──────────────────────────────────────────────────

header "3. Docker stack"

if docker compose config >/dev/null 2>&1; then
  pass "docker-compose.yml is valid"
else
  fail "docker-compose.yml parse error"
fi

XRAY_UP=false
NGINX_UP=false
if docker compose ps --status running xray 2>/dev/null | grep -q "Up"; then
  XRAY_UP=true
  pass "xray container is running"
else
  fail "xray container not running (run: docker compose up -d)"
fi

if docker compose ps --status running nginx 2>/dev/null | grep -q "Up"; then
  NGINX_UP=true
  pass "nginx container is running"
else
  fail "nginx container not running"
fi

if $XRAY_UP; then
  if docker compose exec -T xray pgrep xray >/dev/null 2>&1; then
    pass "xray process is healthy"
  else
    fail "xray process not found inside container"
  fi
fi

if $NGINX_UP; then
  if docker compose exec -T nginx curl -sf http://localhost/ >/dev/null 2>&1; then
    pass "nginx responds on HTTP"
  else
    fail "nginx not responding on HTTP"
  fi

  if docker compose exec -T nginx curl -sfk https://localhost/ >/dev/null 2>&1; then
    pass "nginx responds on HTTPS"
  else
    fail "nginx not responding on HTTPS"
  fi
fi

if $XRAY_UP && $NGINX_UP; then
  HEADER_CHECK=$(docker compose exec -T xray cat /etc/xray/config.json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    clients = len(d['inbounds'][0]['settings']['clients'])
    print(clients)
except: print('err')" 2>/dev/null)
  if [ "$HEADER_CHECK" = "err" ] || [ -z "$HEADER_CHECK" ]; then
    fail "could not read xray config.json"
  else
    pass "xray config.json has $HEADER_CHECK client(s)"
  fi
fi

# Check host port availability
host_http="${HTTP_PORT:-80}"
host_https="${HTTPS_PORT:-443}"
if lsof -ti :"$host_http" 2>/dev/null | head -1 | grep -q .; then
  warn "Host port $host_http (HTTP) is already in use by PID $(lsof -ti :$host_http 2>/dev/null | head -1)"
else
  pass "Host port $host_http (HTTP) is free"
fi
if lsof -ti :"$host_https" 2>/dev/null | head -1 | grep -q .; then
  warn "Host port $host_https (HTTPS) is already in use by PID $(lsof -ti :$host_https 2>/dev/null | head -1)"
else
  pass "Host port $host_https (HTTPS) is free"
fi
# When containers are running, ports are occupied by design
if $NGINX_UP; then
  warn "Ports $host_http/$host_https are occupied by nginx container (expected)"
fi

# ──────────────────────────────────────────────────

header "4. Decoy site"

if $NGINX_UP; then
  STATUS=$(docker compose exec -T nginx curl -sk -o /dev/null -w "%{http_code}" https://localhost/ 2>/dev/null)
  if [ "$STATUS" = "200" ]; then
    pass "Decoy site returns HTTP $STATUS"
  else
    fail "Decoy site returned HTTP $STATUS (expected 200)"
  fi

  TITLE=$(docker compose exec -T nginx curl -sk https://localhost/ 2>/dev/null | sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p')
  if [ -n "$TITLE" ]; then
    pass "Decoy title: $TITLE"
  fi
else
  skip "decoy site checks (nginx not running)"
fi

# ──────────────────────────────────────────────────

header "5. Reality connectivity"

if $XRAY_UP && $NGINX_UP; then
  # Test that Reality SNI routing works (connects to real dest, gets its cert)
  if command -v openssl >/dev/null 2>&1; then
    DEST_HOST=$(echo "$DEST" | cut -d: -f1)
    REALITY_OK=$(timeout 5 sh -c "echo | openssl s_client -connect 127.0.0.1:$host_https -servername $DEST_HOST 2>/dev/null" | openssl x509 -noout -subject 2>/dev/null | head -1)
    if [ -n "$REALITY_OK" ]; then
      pass "Reality proxy responds (cert subject: $REALITY_OK)"
    else
      fail "Reality proxy not responding on $host_https with SNI=$DEST_HOST"
    fi
  else
    warn "openssl not installed — skipping Reality connectivity test"
  fi
fi

if [ -n "$PRIVKEY" ] && [ "$PRIVKEY" != "CHANGE_ME" ]; then
  PUBKEY=$(xray x25519 -i "$PRIVKEY" 2>/dev/null | grep "PublicKey" | awk '{print $NF}' | tr -d '\r') || true
  if [ -n "$PUBKEY" ]; then
    pass "Public key derivable from private key: ${PUBKEY}..."
  else
    fail "Cannot derive public key from private key (xray binary needed)"
  fi
fi

# ──────────────────────────────────────────────────

header "6. Systemd service"

SERVICE_FILE="/etc/systemd/system/xray-stack.service"
if [ -f "$SERVICE_FILE" ]; then
  pass "systemd service file exists"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-enabled xray-stack >/dev/null 2>&1; then
      pass "xray-stack service is enabled"
    else
      fail "xray-stack service not enabled (run: systemctl enable xray-stack)"
    fi
    if systemctl is-active xray-stack >/dev/null 2>&1; then
      pass "xray-stack service is active"
    else
      warn "xray-stack service not active (expected if stack managed manually)"
    fi
  fi
else
  if [ -f xray-stack.service ]; then
    warn "systemd service not installed (run: sudo cp xray-stack.service /etc/systemd/system/ && sudo systemctl enable xray-stack)"
  else
    warn "xray-stack.service file missing from project"
  fi
fi

# ──────────────────────────────────────────────────

header "7. SSL / Certbot"

SSL_PATH="${SSL_DIR:-./ssl}"
if [ -d "$SSL_PATH" ]; then
  if [ -f "$SSL_PATH/fullchain.pem" ] && [ -f "$SSL_PATH/privkey.pem" ]; then
    pass "SSL certificates exist in $SSL_PATH"
    # Check expiry
    if command -v openssl >/dev/null 2>&1; then
      EXPIRY=$(openssl x509 -enddate -noout -in "$SSL_PATH/fullchain.pem" 2>/dev/null | cut -d= -f2) || true
      if [ -n "$EXPIRY" ]; then
        pass "Certificate expires: $EXPIRY"
      fi
    fi
  else
    warn "SSL directory exists but missing fullchain.pem or privkey.pem"
  fi
else
  warn "SSL directory $SSL_PATH not found (self-signed cert used inside container)"
fi

LE_HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
if [ -f "$LE_HOOK" ]; then
  pass "Certbot deploy hook installed"
  if grep -q "$DECOY" "$LE_HOOK" 2>/dev/null; then
    pass "Deploy hook references correct domain ($DECOY)"
  else
    warn "Deploy hook may not reference your domain ($DECOY)"
  fi
else
  if [ "$DECOY" != "example.com" ] && [ "$DECOY" != "localhost" ]; then
    warn "Certbot deploy hook not installed (run: sudo cp reload-nginx.hook $LE_HOOK && sudo chmod +x $LE_HOOK)"
  fi
fi

# ──────────────────────────────────────────────────

header "8. Security"

if [ -f .env ]; then
  PERMS=$(stat -f "%Lp" .env 2>/dev/null || stat -c "%a" .env 2>/dev/null)
  if [ "$PERMS" = "600" ] || [ "$PERMS" = "400" ]; then
    pass ".env permissions: $PERMS"
  else
    warn ".env permissions: $PERMS (recommend: chmod 640 .env, or 600 if owned by your user)"
  fi
fi

if $XRAY_UP; then
  if docker inspect xray --format '{{.HostConfig.CapDrop}}' 2>/dev/null | grep -q "ALL"; then
    pass "xray container: cap_drop ALL"
  else
    warn "xray container: cap_drop not ALL"
  fi
fi

# ──────────────────────────────────────────────────

header "9. Scripts"

for script in add_user.sh list_users.sh host_setup.sh; do
  if [ -f "$script" ]; then
    if [ -x "$script" ]; then
      pass "$script is executable"
    else
      fail "$script not executable (run: chmod +x $script)"
    fi
  else
    fail "$script missing"
  fi
done

# ──────────────────────────────────────────────────

echo ""
if [ "$fail_count" -eq 0 ]; then
  printf "${GREEN}${BOLD}✓ All checks passed${NC}\n"
else
  printf "${RED}${BOLD}✗ $fail_count check(s) failed${NC}\n"
fi
exit $fail_count

#!/bin/sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok() { printf "  ${GREEN}✓${NC} %s\n" "$*"; }
warn() { printf "  ${YELLOW}⚠${NC} %s\n" "$*"; }
fail() { printf "  ${RED}✗${NC} %s\n" "$*"; }

STACK_DIR="/opt/xray-stack"
BACKUP_DIR="/tmp/xray-update-$(date +%s)"

cd "$STACK_DIR"

# 1. Save user files
mkdir -p "$BACKUP_DIR"
cp .env "$BACKUP_DIR/" 2>/dev/null || true
cp -r nginx/html "$BACKUP_DIR/" 2>/dev/null || true
cp -r ssl "$BACKUP_DIR/" 2>/dev/null || true
ok "User files backed up to $BACKUP_DIR"

# 2. Git pull
if git pull origin main 2>&1; then
  ok "Git pull done"
else
  warn "Git pull failed, trying fetch+reset"
  git fetch origin
  git reset --hard origin/main
  ok "Git reset to origin/main"
fi

CURRENT=$(git log --oneline -1)
ok "Now at: $CURRENT"

# 3. Restore user files
cp "$BACKUP_DIR/.env" .env 2>/dev/null && ok ".env restored" || warn ".env not found"
if [ -d "$BACKUP_DIR/html" ] && [ "$(ls -A "$BACKUP_DIR/html" 2>/dev/null)" ]; then
  cp -r "$BACKUP_DIR/html" nginx/ && ok "Decoy site restored"
fi
if [ -d "$BACKUP_DIR/ssl" ] && [ "$(ls -A "$BACKUP_DIR/ssl" 2>/dev/null)" ]; then
  cp -r "$BACKUP_DIR/ssl" . && ok "SSL certs restored"
fi

# 4. Check .env still present
if [ ! -f .env ]; then
  fail ".env missing after update"
  exit 1
fi

# 5. Rebuild & restart
if docker compose build --pull 2>&1; then
  ok "Images rebuilt"
fi

if docker compose up -d 2>&1; then
  ok "Stack restarted"
else
  fail "docker compose up failed"
  exit 1
fi

# 6. Health check
sleep 5
if docker compose ps --status running xray 2>/dev/null | grep -q "Up"; then
  ok "xray is running"
else
  fail "xray not running"
fi
if docker compose ps --status running nginx 2>/dev/null | grep -q "Up"; then
  ok "nginx is running"
else
  fail "nginx not running"
fi

echo ""
printf "${GREEN}${BOLD}✓ Update complete${NC}\n"
echo "Rollback: cp -r $BACKUP_DIR/* $STACK_DIR/ && docker compose up -d"

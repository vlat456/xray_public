#!/bin/sh
set -e

command -v python3 >/dev/null 2>&1 || { echo "Error: python3 required. Install: apt install python3 (Debian/Ubuntu) or dnf install python3 (RHEL)"; exit 1; }

if [ ! -f .env ]; then
  echo "Error: .env not found. Copy from .env.example and configure."
  exit 1
fi

exec python3 -c "
import os, subprocess, sys, urllib.parse

env = {}
with open('.env') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        k, _, v = line.partition('=')
        env[k.strip()] = v.strip().strip(\"'\").strip('\"')

clients_str = env.get('XRAY_CLIENTS', '')
if not clients_str or clients_str == 'CHANGE_ME':
    print('No clients configured.')
    sys.exit(0)

clients = []
for c in clients_str.split(';'):
    c = c.strip()
    if not c:
        continue
    if ',' in c:
        uuid, name = c.split(',', 1)
    else:
        uuid, name = c, '-'
    clients.append((uuid.strip(), name.strip()))

if not clients:
    print('No clients configured.')
    sys.exit(0)

privkey = env.get('XRAY_REALITY_PRIVATE_KEY', '')
pubkey = ''
if privkey and privkey != 'CHANGE_ME':
    try:
        r = subprocess.run(
            ['docker', 'compose', 'exec', '-T', 'xray', 'xray', 'x25519', '-i', privkey],
            capture_output=True, text=True, timeout=10
        )
        for line in r.stdout.splitlines():
            if 'PublicKey' in line:
                pubkey = line.split()[-1].strip()
                break
    except Exception:
        pass
    if not pubkey:
        try:
            r = subprocess.run(
                ['xray', 'x25519', '-i', privkey],
                capture_output=True, text=True, timeout=10
            )
            for line in r.stdout.splitlines():
                if 'PublicKey' in line:
                    pubkey = line.split()[-1].strip()
                    break
        except Exception:
            pass

server = env.get('DECOY_DOMAIN', 'CHANGE_ME')
port = env.get('NGINX_HTTPS_PORT', '443')
dest = env.get('XRAY_REALITY_DEST', 'steamcommunity.com:443')
sni = env.get('XRAY_REALITY_SERVER_NAMES', '') or dest.split(':')[0]
short_ids = env.get('XRAY_REALITY_SHORT_IDS', '')
sid = short_ids.split(',')[0] if short_ids else 'cbdc51eb'
flow = 'xtls-rprx-vision'

GREEN = '\033[0;32m'
CYAN = '\033[0;36m'
YELLOW = '\033[1;33m'
BOLD = '\033[1m'
NC = '\033[0m'

print()
print(f'{BOLD}{GREEN}📋 Xray Clients{NC}')
print()
for i, (uuid, name) in enumerate(clients, 1):
    print(f'  {YELLOW}👤{NC} {BOLD}{name}{NC}')
    print(f'    {CYAN}🔑{NC} UUID: {uuid}')
    if pubkey:
        fragment = f'#{name}' if name != '-' else ''
        vless = f'vless://{uuid}@{server}:{port}?type=tcp&security=reality&flow={flow}&sni={sni}&fp=chrome&pbk={pubkey}&sid={sid}{fragment}'
        qr = 'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=' + urllib.parse.quote(vless)
        print(f'    {CYAN}🔗{NC} VLESS: {vless}')
        print(f'    {CYAN}📱{NC} QR:    {qr}')
    print()
"

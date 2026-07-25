#!/bin/sh
set -e

# Generate xray config from env vars
CLIENTS_JSON=""
CLIENTS_JSON_NOFLOW=""
IFS=';'
for client in $XRAY_CLIENTS; do
  case "$client" in
    *,*) id="${client%,*}" ; email="${client#*,}" ;;
    *)   id="$client" ; email="" ;;
  esac
  [ -n "$CLIENTS_JSON" ] && CLIENTS_JSON="$CLIENTS_JSON," && CLIENTS_JSON_NOFLOW="$CLIENTS_JSON_NOFLOW,"
  CLIENTS_JSON="$CLIENTS_JSON{\"id\":\"$id\",\"flow\":\"xtls-rprx-vision\""
  CLIENTS_JSON_NOFLOW="$CLIENTS_JSON_NOFLOW{\"id\":\"$id\""
  [ -n "$email" ] && CLIENTS_JSON="$CLIENTS_JSON,\"email\":\"$email\"" && CLIENTS_JSON_NOFLOW="$CLIENTS_JSON_NOFLOW,\"email\":\"$email\""
  CLIENTS_JSON="$CLIENTS_JSON}"
  CLIENTS_JSON_NOFLOW="$CLIENTS_JSON_NOFLOW}"
done
unset IFS

# Build serverNames JSON array
# If XRAY_REALITY_SERVER_NAMES not set, derive from XRAY_REALITY_DEST (strip :port)
SERVER_NAMES="${XRAY_REALITY_SERVER_NAMES:-$(echo "$XRAY_REALITY_DEST" | sed 's/:.*//')}"
NAMES_JSON=""
IFS=','
for name in $SERVER_NAMES; do
  [ -n "$NAMES_JSON" ] && NAMES_JSON="$NAMES_JSON,"
  NAMES_JSON="$NAMES_JSON\"$(echo "$name" | xargs)\""
done
unset IFS

# Build shortIds JSON array
SIDS_JSON=""
IFS=','
for sid in $XRAY_REALITY_SHORT_IDS; do
  [ -n "$SIDS_JSON" ] && SIDS_JSON="$SIDS_JSON,"
  SIDS_JSON="$SIDS_JSON\"$(echo "$sid" | xargs)\""
done
unset IFS

mkdir -p /etc/xray /var/log/xray

# Build config via jq-style heredoc to avoid shell injection
CLIENTS_JSON="$CLIENTS_JSON" CLIENTS_JSON_NOFLOW="$CLIENTS_JSON_NOFLOW" \
  NAMES_JSON="$NAMES_JSON" SIDS_JSON="$SIDS_JSON" \
  XRAY_LOG_LEVEL="$XRAY_LOG_LEVEL" \
  XRAY_REALITY_DEST="$XRAY_REALITY_DEST" \
  XRAY_REALITY_PRIVATE_KEY="$XRAY_REALITY_PRIVATE_KEY" \
  XRAY_XHTTP_MODE="${XRAY_XHTTP_MODE:-auto}" \
  XRAY_XHTTP_PATH="${XRAY_XHTTP_PATH:-/}" \
  python3 -c '
import json, os

def inbound(port, tag, clients_key):
    s = {
        "network": "tcp" if "tcp" in tag else "xhttp",
        "security": "reality",
        "realitySettings": {
            "show": False, "dest": os.environ["XRAY_REALITY_DEST"], "xver": 0,
            "serverNames": json.loads("[" + os.environ["NAMES_JSON"] + "]"),
            "privateKey": os.environ["XRAY_REALITY_PRIVATE_KEY"],
            "shortIds": json.loads("[" + os.environ["SIDS_JSON"] + "]")
        },
        "packetEncoding": "xudp"
    }
    if "tcp" in tag:
        s["tcpSettings"] = {"header": {"type": "none"}}
    else:
        s["xhttpSettings"] = {"mode": os.environ["XRAY_XHTTP_MODE"], "path": os.environ["XRAY_XHTTP_PATH"]}
    return {
        "listen": "0.0.0.0", "port": port, "protocol": "vless", "tag": tag,
        "settings": {"clients": json.loads("[" + os.environ[clients_key] + "]"), "decryption": "none"},
        "streamSettings": s,
        "sniffing": {"enabled": True, "destOverride": ["http", "tls"]}
    }

config = {
    "log": {"loglevel": os.environ["XRAY_LOG_LEVEL"], "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log"},
    "inbounds": [
        inbound(10443, "vless-tcp", "CLIENTS_JSON"),
        inbound(10444, "vless-xhttp", "CLIENTS_JSON_NOFLOW")
    ],
    "outbounds": [
        {"protocol": "freedom", "tag": "direct"},
        {"protocol": "blackhole", "tag": "block"}
    ]
}
with open("/etc/xray/config.json", "w") as f:
    json.dump(config, f, indent=2)
'

echo "[xray] Config generated. Starting xray..."
exec xray run -c /etc/xray/config.json

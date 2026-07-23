#!/bin/sh
set -e

# Generate xray config from env vars
CLIENTS_JSON=""
IFS=';'
for client in $XRAY_CLIENTS; do
  case "$client" in
    *,*) id="${client%,*}" ; email="${client#*,}" ;;
    *)   id="$client" ; email="" ;;
  esac
  [ -n "$CLIENTS_JSON" ] && CLIENTS_JSON="$CLIENTS_JSON,"
  FLOW_STR="xtls-rprx-vision"
  [ "${XRAY_NETWORK:-tcp}" = "xhttp" ] && FLOW_STR=""
  CLIENTS_JSON="$CLIENTS_JSON{\"id\":\"$id\",\"flow\":\"$FLOW_STR\""
  [ -n "$email" ] && CLIENTS_JSON="$CLIENTS_JSON,\"email\":\"$email\""
  CLIENTS_JSON="$CLIENTS_JSON}"
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
CLIENTS_JSON="$CLIENTS_JSON" NAMES_JSON="$NAMES_JSON" SIDS_JSON="$SIDS_JSON" \
  XRAY_LOG_LEVEL="$XRAY_LOG_LEVEL" \
  XRAY_REALITY_DEST="$XRAY_REALITY_DEST" \
  XRAY_REALITY_PRIVATE_KEY="$XRAY_REALITY_PRIVATE_KEY" \
  XRAY_NETWORK="${XRAY_NETWORK:-tcp}" \
  XRAY_XHTTP_MODE="${XRAY_XHTTP_MODE:-auto}" \
  XRAY_XHTTP_PATH="${XRAY_XHTTP_PATH:-/}" \
  python3 -c '
import json, os
network = os.environ["XRAY_NETWORK"]
stream_settings = {
  "network": network,
  "security": "reality",
  "realitySettings": {
    "show": False,
    "dest": os.environ["XRAY_REALITY_DEST"],
    "xver": 0,
    "serverNames": json.loads("[" + os.environ["NAMES_JSON"] + "]"),
    "privateKey": os.environ["XRAY_REALITY_PRIVATE_KEY"],
    "shortIds": json.loads("[" + os.environ["SIDS_JSON"] + "]")
  },
  "packetEncoding": "xudp"
}
if network == "xhttp":
  stream_settings["xhttpSettings"] = {
    "mode": os.environ["XRAY_XHTTP_MODE"],
    "path": os.environ["XRAY_XHTTP_PATH"]
  }
else:
  stream_settings["tcpSettings"] = {"header": {"type": "none"}}
config = {
  "log": {
    "loglevel": os.environ["XRAY_LOG_LEVEL"],
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 10443,
    "protocol": "vless",
    "tag": "vless-in",
    "settings": {
      "clients": json.loads("[" + os.environ["CLIENTS_JSON"] + "]"),
      "decryption": "none"
    },
    "streamSettings": stream_settings,
    # --sniffing
    "sniffing": {
      "enabled": True,
      "destOverride": ["http", "tls"]
    }
  }],
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

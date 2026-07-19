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
  CLIENTS_JSON="$CLIENTS_JSON{\"id\":\"$id\",\"flow\":\"xtls-rprx-vision\""
  [ -n "$email" ] && CLIENTS_JSON="$CLIENTS_JSON,\"email\":\"$email\""
  CLIENTS_JSON="$CLIENTS_JSON}"
done
unset IFS

# Build serverNames JSON array
NAMES_JSON=""
IFS=','
for name in $XRAY_REALITY_SERVER_NAMES; do
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
cat > /etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "${XRAY_LOG_LEVEL}",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 10443,
      "protocol": "vless",
      "tag": "vless-in",
      "settings": {
        "clients": [$CLIENTS_JSON],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${XRAY_REALITY_DEST}",
          "xver": 0,
          "serverNames": [$NAMES_JSON],
          "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
          "shortIds": [$SIDS_JSON]
        },
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        },
        "packetEncoding": "xudp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

echo "[xray] Config generated. Starting xray..."
exec xray run -c /etc/xray/config.json

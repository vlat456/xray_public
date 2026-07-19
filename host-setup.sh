#!/bin/sh
set -e

echo "=== Host setup for xray Reality stack ==="

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  OS=$(uname -s)
fi

echo "OS detected: $OS"

# 1. TCP kernel tuning
cat > /etc/sysctl.d/90-tune.conf <<'SYSCTL'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
net.core.somaxconn=4096
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_mtu_probing=1
SYSCTL
sysctl -p /etc/sysctl.d/90-tune.conf

# 2. Install Docker
case "$OS" in
  debian|ubuntu)
    apt-get update -qq
    apt-get install -y -qq docker.io docker-compose-v2 certbot
    ;;

  rocky|rhel|centos|almalinux)
    dnf install -y -q dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y -q docker-ce certbot
    systemctl enable --now docker
    ;;

  *)
    echo "Unknown OS: $OS"
    echo "Install Docker manually, open ports 80, 443"
    ;;
esac

# 3. Copy .env if not exists
if [ ! -f .env ]; then
  cp .env.example .env
  echo ".env created from .env.example — edit it before starting"
fi

echo "=== Done ==="
echo "Next: edit .env, then run: docker compose up -d"

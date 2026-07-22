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
net.core.somaxconn=65535
net.core.netdev_max_backlog=5000
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=131072
vm.overcommit_memory=1
vm.swappiness=10
SYSCTL
sysctl -p /etc/sysctl.d/90-tune.conf

# 2. Install Docker
case "$OS" in
  debian|ubuntu)
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl python3
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$ID/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-compose-plugin certbot
    ;;

  rocky|rhel|centos|almalinux)
    dnf install -y -q dnf-plugins-core python3
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

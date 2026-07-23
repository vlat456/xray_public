# Changelog

## 2026-07-23

### Fixed
- **list_users.sh**: shortId назначается round-robin, а не один на всех
- **post_check.sh**: HTTPS тест через `--resolve $DECOY` вместо `localhost` (ложный 400)
- **post_check.sh**: получение публичного ключа через `docker compose exec xray`

### Docs
- **INSTALL.md**: добавлены грабли 18.9–18.11 (post_check HTTPS, fwupd память, shortId diversity)

### DevOps
- **90-tune.conf**: `tcp_slow_start_after_idle=0`, `tcp_notsent_lowat=131072`, `netdev_max_backlog=5000`, `tcp_max_syn_backlog=8192`, `overcommit_memory=1`, `swappiness=10`
- **host-setup.sh**:синхронизирован с 90-tune.conf (новые sysctl-параметры)
- **fwupd**: отключён (жрёт 210MB RAM на Ubuntu 24.04)

## 2026-07-21

### Fixed
- **entrypoint.sh**: корректный парсинг email через `case` вместо `cut` (Alpine busybox)
- **nginx.conf**: `resolver 127.0.0.11` для upstream xray (host not found при старте)
- **docker-compose.yml**: `:ro` убран с decoy html mount, self-signed серт в Dockerfile

### Added
- **add-user.sh**: скрипт добавления клиентов с авто-генерацией UUID и публичного ключа
- **post_check.sh**: скрипт проверки стека после развёртывания
- **xray-stack.service**: systemd unit для автостарта стека
- **reload-nginx.hook**: deploy hook для certbot (zero-downtime reload)

### Docs
- **INSTALL.md**: полная документация по установке, известные проблемы

## 2026-07-15

### Added
- **Initial release**: Xray (VLESS + Reality) + Nginx (ssl_preread) stack

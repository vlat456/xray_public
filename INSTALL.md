# Инструкция по развертыванию Xray (VLESS + Reality + Nginx) в Docker

Данный стек предназначен для быстрого развертывания Xray с протоколом **VLESS + Reality** за прокси-сервером Nginx (с использованием SNI-мультиплексирования `ssl_preread`), что позволяет обходить блокировки (включая ТСПУ) и маскировать трафик под легитимные сайты.

---

## Требования
* ОС: Linux (Debian, Ubuntu, Rocky Linux, RHEL, AlmaLinux) или macOS (для локального тестирования).
* Установленный Docker и Docker Compose.

---

## Быстрый старт

### 1. Подготовка хоста (только для Linux VPS)
Запустите скрипт для оптимизации сетевых настроек TCP (включение BBR, TCP Fast Open) и автоматической установки Docker:
```bash
sudo ./host-setup.sh
```
Не забудьте самостоятельно открыть порты `80` и `443` (или ваши кастомные порты) в брандмауэре хоста.


### 2. Настройка конфигурации (.env)
Создайте файл `.env` из примера (если еще не создан) и заполните его:
```bash
cp .env.example .env
```

Отредактируйте переменные в `.env`:
* `XRAY_REALITY_PRIVATE_KEY` — Ваш приватный Reality ключ (сгенерируйте новый с помощью команды `docker compose run --rm xray xray x25519`).
* `XRAY_CLIENTS` — UUID пользователей через **точку с запятой `;`** в формате `UUID,email;UUID2,email2`. ВНИМАНИЕ: разделитель между клиентами — `;`, не `,`. Запятая внутри пары отделяет email от UUID.
* `DECOY_DOMAIN` — Домен сайта-приманки (декоя), на который Nginx будет отправлять всех обычных посетителей (например, `example.com`).
* `DECOY_HTML_DIR` — Путь к папке на хосте, содержащей файлы сайта-приманки (монтируется в `/var/www/html`). Если папка пуста, сгенерируется дефолтный шаблон.
* `SSL_DIR` — Путь к директории с сертификатами. LE deploy hook копирует сюда свежие серты, nginx перечитывает по SIGHUP. По умолчанию `./ssl` — самоподписанный серт встроен в образ.
* `NGINX_HTTP_PORT` и `NGINX_HTTPS_PORT` — Внешние порты. На VPS оставьте `80` и `443`. На macOS (где эти порты обычно заняты) вы можете указать любые свободные порты (например, `18080` и `18443`).

### 3. Запуск стека
Запустите контейнеры в фоновом режиме:
```bash
docker compose up -d
```

Проверить статус контейнеров можно командой:
```bash
docker compose ps
```

---

## Управление пользователями

Для добавления нового клиента выполните команду на сервере:
```bash
./add-user.sh "имя-клиента"
```

Скрипт автоматически:
1. Определит, запущен ли Docker-окружение.
2. Сгенерирует новый UUID.
3. Получит соответствующий публичный ключ (Reality Public Key) из контейнера xray.
4. Добавит нового клиента в ваш `.env`.
5. Перезапустит контейнер `xray` для применения настроек.
6. Выведет готовую VLESS-ссылку для импорта в клиент (например, v2rayN, Nekobox, Sing-box).

---

## Systemd сервис

Для автостарта стека при загрузке системы:

```bash
sudo cp xray-stack.service /etc/systemd/system/
sudo systemctl enable xray-stack
```

Сервис управляет `docker compose up -d` при старте и `docker compose down` при остановке.

---

## Обновление LE сертификатов

Certbot обновляет сертификаты автоматически по таймеру. Механизм:

1. **Directory mount**: `SSL_DIR=./ssl` монтируется как директория (`ro`). Docker следит за именем файла, не за inode — после `cp` новый файл подхватывается.
2. **Deploy hook**: Certbot запускает скрипт после успешного обновления. Скрипт копирует свежие серты из `/etc/letsencrypt/live/` в `./ssl/` и шлет SIGHUP nginx.
3. **SIGHUP reload**: `nginx -s reload` — zero-downtime. Существующие соединения не рвутся, nginx перечитывает конфиг и сертификаты на лету.

Создайте deploy hook:

```bash
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOK'
#!/bin/sh
cp -L /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem /opt/xray-stack/ssl/fullchain.pem
cp -L /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem /opt/xray-stack/ssl/privkey.pem
chown YOUR_USER:YOUR_USER /opt/xray-stack/ssl/*.pem
cd /opt/xray-stack && /usr/bin/docker compose exec -T nginx nginx -s reload
HOOK
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

---

## Проверка работоспособности

Вы можете протестировать корректность маршрутизации Nginx с помощью `curl`:

1. **Проверка сайта-приманки (запрос с корректным SNI декоя)**:
   ```bash
   curl -k --resolve <DECOY_DOMAIN>:<HTTPS_PORT>:127.0.0.1 https://<DECOY_DOMAIN>:<HTTPS_PORT>
   ```
   Должен вернуться HTML-код вашего фейкового сайта (или дефолтный шаблон).

2. **Проверка перенаправления Xray (запрос с любым другим SNI, например, steamcommunity.com)**:
   При отправке запроса с отличным от декоя SNI, Nginx автоматически проксирует TCP-поток напрямую в Xray.

---

## Известные проблемы и их решения (грабли)

### 1. Alpine `cut` не возвращает пустую строку для отсутствующего поля
**Симптом**: В сгенерированном config.json у всех клиентов поле `email` = UUID.
**Причина**: `echo "uuid" | cut -d, -f2` в Alpine (busybox) возвращает всю строку вместо пустой, если разделитель отсутствует. Стандартный GNU cut возвращает пустую строку.
**Решение**: Заменили `cut -d, -f2` на pure-shell `case` с parameter expansion:
```sh
case "$client" in
  *,*) id="${client%,*}" ; email="${client#*,}" ;;
  *)   id="$client" ; email="" ;;
esac
```

### 2. Docker `ro` mount блокирует запись entrypoint-скрипта
**Симптом**: nginx падает с exit code 1, в логах пусто.
**Причина**: `./nginx/html:/var/www/html:ro` и `./ssl:/etc/nginx/ssl:ro` в docker-compose. Entrypoint пытается записать index.html и self-signed серт, но `ro` mount запрещает запись, `set -e` обрывает скрипт, openssl с `2>/dev/null` скрывает ошибку.
**Решение**: 
- Self-signed серт генерируется в Dockerfile (встроен в образ).
- Для LE сертов используются file mounts (`ro`) только для готовых файлов.
- `DECOY_HTML_DIR` монтируется без `:ro`.

### 3. File mount фиксирует inode — directory mount видит cp
**Симптом**: После обновления LE сертификатов nginx продолжает отдавать старый серт.
**Причина**: File mount (`file:/etc/letsencrypt/...:/etc/nginx/ssl/cert.pem:ro`) фиксирует inode при старте контейнера. Certbot меняет symlink live/ на новый файл (новый inode) — mount все еще держит старый.
**Решение**: Использовать directory mount (`./ssl:/etc/nginx/ssl:ro`). Копировать свежие серты через `cp` (создает новый inode, но mount отслеживает имя файла). Перезагрузка через SIGHUP (`nginx -s reload`) — zero-downtime.

Схема:
```
LE live/ (symlink на archive/)  →  cp -L ./ssl/ (реальный файл)  →  directory mount  →  nginx reload
```

### 4. Nginx `host not found` для Docker DNS при старте (устранено)
**Симптом**: nginx exit 1 при старте, ошибка "host not found in upstream".
**Причина**: nginx резолвит upstream при загрузке конфига. Если xray еще не запустился, Docker DNS не отвечает.
**Решение**: В stream block добавлен `resolver 127.0.0.11 valid=10s;`, upstream задается через `map` + переменную `$backend`. С переменной nginx не резолвит DNS при старте — разрешает на лету через resolver.

### 5. Разделитель в XRAY_CLIENTS: `;` а не `,`
**Симптом**: В config.json только 1 клиент, его email = UUID следующего клиента.
**Причина**: Entrypoint парсит `XRAY_CLIENTS` через `IFS=';'`, а в `.env` стояли запятые как разделители. Вся строка воспринималась как 1 клиент, `cut -d, -f2` возвращал второй UUID как email.
**Решение**: Соблюдать формат `uuid1,email1;uuid2;uuid3,email3` в `.env`.

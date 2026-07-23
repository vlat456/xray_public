# Развертывание Xray (VLESS + Reality) в Docker

Этот стек поднимает Xray с протоколом **VLESS + Reality** за Nginx. Nginx анализирует SNI
входящих TLS-соединений и направляет:
- ваш легитимный домен → на сайт-приманку
- всё остальное → в Xray Reality

Таким образом, Xray не виден при сканировании порта — злоумышленник или DPI увидят
обычный сайт, а не прокси.

---

## Что вы получите

```
VPS :443 → Nginx (ssl_preread)
          ├─ ваш-домен → Nginx :1443 (обычный сайт, Let's Encrypt)
          └─ любой другой SNI → Xray :10443 (Reality, трафик маскируется под TLS)
```

---

## 1. Требования

- Чистый VPS с одним из:
  - Debian 11+
  - Ubuntu 22.04+
  - Rocky Linux / RHEL / AlmaLinux 9+
- Root-доступ (или пользователь с `sudo`)
- Домен, привязанный к IP сервера (для сайта-приманки и Let's Encrypt)
- Открытые порты 80 и 443 в файрволе хостера

---

## 2. Подключение к VPS

```bash
ssh root@ВАШ_IP
# или если у вас пользователь:
ssh user@ВАШ_IP
```

---

## 3. Копирование файлов на сервер

Со своего компьютера (не с сервера) скопируйте папку `xray-public` на VPS:

```bash
# Со своего компьютера:
scp -r /путь/до/xray-public user@ВАШ_IP:/opt/xray-stack
```

**Или** склонируйте репозиторий прямо на сервере:

```bash
# Установите git, если его нет
apt update && apt install -y git
# или на RHEL:
dnf install -y git

# Склонируйте
git clone https://github.com/vlat456/xray_public.git /opt/xray-stack
```

---

## 4. Подготовка сервера

Перейдите в папку стека:

```bash
cd /opt/xray-stack
```

Запустите скрипт подготовки. Он:
- Включит BBR (алгоритм TCP, ускоряет соединения)
- Настроит буферы сети
- Установит Docker, Docker Compose и python3

```bash
sudo ./host_setup.sh
```

Скрипт сам определит вашу ОС (Debian, Ubuntu или RHEL-семейство).

После завершения — перезагрузите сервер (рекомендуется, чтобы BBR и новые
настройки ядра применились):

```bash
sudo reboot
```

Через минуту подключитесь заново:

```bash
ssh user@ВАШ_IP
cd /opt/xray-stack
```

---

## 5. Настройка .env

Скопируйте пример конфигурации:

```bash
cp .env.example .env
```

Откройте для редактирования:

```bash
nano .env
# или vim .env, если умеете
```

### 5.1. Приватный ключ Reality

**Обязательно сгенерируйте свой, не используйте пример!**

```bash
docker run --rm --entrypoint xray ghcr.io/xtls/xray-core:latest x25519
```

Вы увидите:

```
PrivateKey: 6NZM9cHXszxAgqnVaQ9jWVb-9aRe8tZYD76IBWaIFG4
Password (PublicKey): BNY0n7LMKr8ZckF-L-58C0VDK4smr94bPhdDgoXAvXY
Hash32: kDQykacemZ3p9txNKtFA9y0Al0jsPkj8myu8-g7EEG4
```

Скопируйте `PrivateKey` (это секретный ключ, никому не говорите).
PublicKey понадобится клиентам для подключения.

В `.env` найдите строку:

```
XRAY_REALITY_PRIVATE_KEY=CHANGE_ME
```

Замените `CHANGE_ME` на ваш PrivateKey:

```
XRAY_REALITY_PRIVATE_KEY=6NZM9cHXszxAgqnVaQ9jWVb-9aRe8tZYD76IBWaIFG4
```

**Храните этот ключ в секрете**. С ним можно расшифровать трафик.

### 5.2. Адрес назначения (dest)

Это адрес, под который маскируется Reality-трафик. По умолчанию —
`steamcommunity.com:443`. Можно оставить как есть или указать другой
популярный сайт с TLSv1.3:

- `microsoft.com:443`
- `cloudflare.com:443`
- `google.com:443`

```
XRAY_REALITY_DEST=steamcommunity.com:443
```

`XRAY_REALITY_SERVER_NAMES` выставляется автоматически из домена dest.
Если нужно переопределить — задайте переменную явно.

### 5.3. Short IDs

Короткие идентификаторы Reality для маскировки. Можно оставить как есть,
но можно сгенерировать свои:

```bash
openssl rand -hex 4
```

В `.env` они указываются через запятую:

```
XRAY_REALITY_SHORT_IDS=cbdc51eb,7ae88f24,f3116322,94571650,92e2b18e,a38c78ef
```

**ВАЖНО: КАЖДОМУ КЛИЕНТУ ВЫДАВАЙТЕ УНИКАЛЬНЫЙ SHORT ID**, а не один на всех.
На сервере прописаны все shortIds, на клиенте указывается один. Список в `XRAY_REALITY_SHORT_IDS`.
Сгенерировать новый: `openssl rand -hex 4` — и добавить в эту переменную.

### 5.4. Клиенты (UUID)

На этом этапе клиентов **не добавляйте** — это можно сделать позже через
`add_user.sh` без перезапуска стека. Просто оставьте:

```
XRAY_CLIENTS=CHANGE_ME
```

Формат (для справки, пригодится если править `.env` вручную):

```
XRAY_CLIENTS=UUID1,имя1;UUID2,имя2;UUID3
```

Где:
- `;` — разделитель между клиентами
- `,` — отделяет человекочитаемый идентификатор (имя) от UUID (опционален)
- UUID генерируется командой: `uuidgen` или `python3 -c "import uuid; print(uuid.uuid4())"`
- Имя добавляется в конец VLESS-ссылки после `#` — клиентское приложение покажет его как название подключения

Пример:

```
XRAY_CLIENTS=550e8400-e29b-41d4-a716-446655440000,alice
```

### 5.5. Домен сайта-приманки (decoy)

Укажите ваш реальный домен, привязанный к IP сервера:

```
DECOY_DOMAIN=example.com
DECOY_TITLE=IT Consultancy — Example Corp
```

На этот домен Nginx будет показывать обычный сайт. Название сайта
можно задать через `DECOY_TITLE`.

### 5.6. Порты

На VPS всегда ставьте:

```
NGINX_HTTP_PORT=80
NGINX_HTTPS_PORT=443
```

Эти порты должен открыть скрипт `host_setup.sh` (он установит Docker,
но файрвол вам придётся настроить самостоятельно, см. шаг 8).

Порты `80` и `443` нужны для Let's Encrypt (получение сертификата).

### 5.8. Транспорт: TCP или XHTTP

По умолчанию Xray использует транспорт TCP. Можно включить **XHTTP** —
мультиплексированный транспорт поверх HTTP/1.1 и H2C:

```
# XRAY_NETWORK=tcp     # TCP (по умолчанию)
# XRAY_NETWORK=xhttp   # XHTTP (мультиплексирование)
# XRAY_XHTTP_MODE=auto # auto | h1 | h2
# XRAY_XHTTP_PATH=/    # path prefix
```

XHTTP даёт:
- Мультиплексирование потоков поверх одного TCP-соединения (как gRPC/QUIC)
- Меньше overhead при большом числе одновременных подключений
- Работает поверх Reality (маскировка сохраняется)

**Важно:** XHTTP несовместим с `flow: xtls-rprx-vision`. Клиентам нужно
указывать пустой flow (или не указывать). `add_user.sh` сам определяет
XRAY_NETWORK и генерирует правильную VLESS-ссылку.

**XHTTP без Reality не заработает.** Nginx анализирует SNI на основе TLS
ClientHello. Если `security: "none"` (чистый XHTTP h1/h2c) — TLS-слоя нет,
nginx не сможет определить SNI и направить трафик. В entrypoint `security: "reality"`
стоит всегда, поэтому с данным стеком XHTTP работает корректно.

### 5.9. Директория SSL

Если у вас есть сертификаты Let's Encrypt — укажите путь к папке,
куда они будут скопированы (скрипт deploy hook делает это автоматически).

Если сертификатов нет — оставьте `SSL_DIR=./ssl`. В контейнере уже
встроен самоподписанный сертификат, nginx запустится и с ним.

---

## 6. Первый запуск

```bash
docker compose up -d --build
```

Параметр `--build` нужен только при первом запуске, чтобы собрать образы.

Что произойдёт:
1. Docker соберёт образ Xray (alpine + python3 + xray-core)
2. Docker соберёт образ Nginx (alpine + openssl + curl)
3. Запустится контейнер `xray` — entrypoint.sh прочитает `.env`
   и сгенерирует `config.json`
4. Запустится контейнер `nginx` — entrypoint.sh сгенерирует
   конфиг nginx и стартует его
5. Nginx начнёт слушать порты 80 и 443, перенаправляя трафик
   по SNI на Xray или на сайт-приманку

Проверьте статус:

```bash
docker compose ps
```

Ожидаемый вывод:

```
NAME      IMAGE               SERVICE   STATUS         PORTS
nginx     xray-public-nginx   nginx     Up 5 seconds   0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
xray      xray-public-xray    xray      Up 5 seconds   10443/tcp
```

### Пост-установочная проверка

Запустите `post_check.sh` — он проверит каждый компонент стека:

```bash
./post_check.sh
```

Скрипт проходит 9 секций: prereqs, .env корректность, Docker stack, decoy site,
Reality, systemd, SSL, безопасность, скрипты. Всё, что подсвечено красным —
нужно исправить перед использованием.

Ошибки — смотрите логи:

```bash
docker compose logs xray
docker compose logs nginx
```

---

## 7. Проверка без Let's Encrypt

Перед получением сертификатов можно проверить, что Nginx и Xray
работают, через localhost:

```bash
# Проверка сайта-приманки (через самоподписанный серт)
# Замените ВАШ_ДОМЕН на ваш DECOY_DOMAIN
curl -k --resolve ВАШ_ДОМЕН:443:127.0.0.1 https://ВАШ_ДОМЕН

# Проверка SNI-роутинга в Xray
# Используем SNI отличный от decoy — Nginx направит в Xray
# Специального ответа не будет (Reality — это не HTTP), но соединение
# не должно сбрасываться
timeout 3 bash -c "echo | openssl s_client -connect 127.0.0.1:443 -servername steamcommunity.com 2>/dev/null" | head -5
```

---

## 8. Файрвол

Обязательно откройте порты в файрволе ОС. Пример для ufw (Debian/Ubuntu):

```bash
ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # HTTP (для Let's Encrypt)
ufw allow 443/tcp     # HTTPS (Xray + decoy)
ufw enable
```

Для firewalld (Rocky/RHEL):

```bash
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload
```

**Проверьте также файрвол у хостера** (DigitalOcean, Vultr, Hetzner и т.д.) —
обычно есть отдельная панель с правилами. Порты 80 и 443 должны быть открыты
и там.

---

## 9. Let's Encrypt (сертификаты)

Чтобы сайт-приманка работал по HTTPS с реальным сертификатом, получите
Let's Encrypt:

```bash
# Остановите nginx (он занимает порт 80)
docker compose stop nginx

# Получите сертификат
sudo certbot certonly --standalone -d ВАШ_ДОМЕН

# Запустите nginx обратно
docker compose start nginx
```

Теперь скопируйте сертификаты в `./ssl/`:

```bash
# Скопируйте свежие серты
cp -L /etc/letsencrypt/live/ВАШ_ДОМЕН/fullchain.pem ./ssl/fullchain.pem
cp -L /etc/letsencrypt/live/ВАШ_ДОМЕН/privkey.pem ./ssl/privkey.pem

# Поправьте права (чтобы контейнер мог читать)
chmod 644 ./ssl/*.pem

# Перезагрузите nginx, чтобы он подхватил новые серты
docker compose exec nginx nginx -s reload
```

### Автообновление сертификатов

Certbot обновляет сертификаты автоматически по таймеру. Но нужно
настроить deploy hook, чтобы он копировал свежие серты в `./ssl/`
и перезагружал nginx:

```bash
sudo mkdir -p /etc/letsencrypt/renewal-hooks/deploy
sudo cp /opt/xray-stack/reload-nginx.hook /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

**Важно:** Отредактируйте файл `/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh`:
- замените `YOUR_DOMAIN` на ваш домен
- замените `YOUR_USER` на вашего пользователя (или `root`)

После этого certbot будет при каждом обновлении:
1. Копировать новые серты в `/opt/xray-stack/ssl/`
2. Посылать nginx-у SIGHUP (zero-downtime reload)

### Проверка после настройки LE

Снова запустите `post_check.sh` — он проверит сертификаты, deploy hook и всё остальное:

```bash
./post_check.sh
```

---

## 10. Добавление пользователей

Добавьте первого пользователя (выполняйте из папки `/opt/xray-stack`):

```bash
./add_user.sh "имя-клиента"
```

Скрипт:
1. Определит что `.env` существует (Docker-окружение)
2. Сгенерирует новый UUID
3. Получит публичный ключ из контейнера xray
4. Добавит клиента в `.env`
5. Перезапустит xray (на лету, через `docker compose up -d xray`)
6. Выведет VLESS-ссылку и QR-код

Пример вывода:

```
🎉 New client
  🔑 UUID:     7C9EE349-F8CD-4505-ADDE-B7D08543F86C
  👤 username: имя-клиента

  🔗 VLESS: vless://7C9EE349-...@example.com:443?type=tcp&security=reality&flow=xtls-rprx-vision&sni=steamcommunity.com&fp=chrome&pbk=BNY0n7L...&sid=cbdc51eb#имя-клиента
  📱 QR:    https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=vless%3A//...
```

VLESS-ссылку или QR-код можно отсканировать/импортировать в клиент:
- **iPhone:** Streisand, Shadowrocket, V2Box
- **Android:** v2rayNG, NekoBox, SingBox
- **Windows:** v2rayN, Nekoray
- **macOS:** V2Box, sing-box
- **Linux:** sing-box, v2rayA

При импорте приложение само разберёт все параметры из ссылки.

---

## 11. Добавление следующих пользователей

Просто вызовите `add_user.sh` снова:

```bash
./add_user.sh "друг"
./add_user.sh "ноутбук"
```

Каждый раз будет генерироваться новый UUID и новая ссылка.

### Просмотр пользователей

```bash
./list_users.sh
```

Показывает UUID, VLESS-ссылку и QR-код для каждого пользователя.

**Важно:** Если вы переустановили стек или потеряли `.env` — старые
UUID перестанут работать. Храните `.env` в безопасном месте
(но никому не показывайте, там приватный ключ!).

---

## 12. Подключение с клиента

Пример ручной настройки в клиенте:

| Параметр | TCP (по умолчанию) | XHTTP |
|----------|-------------------|-------|
| Протокол | VLESS | VLESS |
| Адрес сервера | ваш-домен | ваш-домен |
| Порт | 443 | 443 |
| UUID | из add_user.sh | из add_user.sh |
| Flow | `xtls-rprx-vision` | (пусто) |
| Encryption | none | none |
| Transport | tcp | xhttp |
| Security (Stream) | Reality | Reality |
| SNI | steamcommunity.com | steamcommunity.com |
| Fingerprint | chrome | chrome |
| PublicKey | из add_user.sh | из add_user.sh |
| ShortId | из add_user.sh | из add_user.sh |

---

## 13. Systemd (автозапуск при перезагрузке)

Чтобы стек запускался автоматически после перезагрузки VPS:

```bash
sudo cp /opt/xray-stack/xray-stack.service /etc/systemd/system/
sudo systemctl enable xray-stack
sudo systemctl start xray-stack
```

Проверить статус:

```bash
systemctl status xray-stack
```

Сервис просто выполняет `docker compose up -d` при старте системы
и `docker compose down` при остановке.

---

## 14. Полезные команды

```bash
# Статус контейнеров
docker compose ps

# Логи Xray
docker compose logs xray

# Логи Nginx
docker compose logs nginx

# Добавить пользователя
./add_user.sh "имя"

# Список пользователей (с VLESS + QR)
./list_users.sh

# Полная проверка установки
./post_check.sh

# Перезапустить Xray (после добавления пользователя)
docker compose up -d xray

# Перезагрузить Nginx (после обновления сертификатов)
docker compose exec nginx nginx -s reload

# Остановить всё
docker compose down

# Запустить всё заново
docker compose up -d
```

---

## 15. Диагностика

### Сайт-приманка не открывается

```bash
# Проверьте, что nginx слушает порты
docker compose ps

# Проверьте логи
docker compose logs nginx

# Проверьте, не занят ли порт 80/443 другим процессом
ss -tlnp | grep -E ':(80|443)\s'
```

### Xray не отвечает

```bash
# Проверьте конфиг, который сгенерировал entrypoint
docker compose exec xray cat /etc/xray/config.json

# Проверьте логи
docker compose logs xray
```

### Сообщение "REALITY: Listening on non-443 ports may get your IP blocked"

Это нормально. Xray внутри контейнера слушает порт 10443.
Наружу смотрит Nginx на 443. Предупреждение можно игнорировать.

### post_check.sh показывает красные пункты

Запустите снова и читайте подсказки — скрипт пишет что делать для каждого
конкретного пункта. Если не помогло — проверьте что вы выполнили все шаги
выше по порядку.

### Не открывается VLESS-ссылка

Проверьте:
- Правильно ли скопировали полную ссылку (от `vless://` до конца)
- Совпадает ли домен в ссылке с вашим реальным доменом
- Открыт ли порт 443 в файрволе
- Работает ли Let's Encrypt (сайт-приманка должен открываться по HTTPS)

---

## 16. Безопасность

- **Приватный ключ Reality (`XRAY_REALITY_PRIVATE_KEY`) — это секрет.**
  Храните `.env` в надёжном месте. Никому не отправляйте.
- **Файл `.env`** должен быть доступен только тому пользователю, из-под которого
  работает стек (иначе `docker compose` не прочитает его):
  ```bash
  chmod 640 .env
  # Или строже, если файл принадлежит вашему пользователю:
  chown $USER:$USER .env && chmod 600 .env
  ```
- **Публичный ключ (`PublicKey`) — не секрет.** Его можно свободно
  распространять клиентам.
- **UUID клиента — не секрет**, но если клиент перестал пользоваться —
  удалите его UUID из `.env`, чтобы он не занимал место.
- Xray в контейнере работает с `cap_drop: ALL` — минимум привилегий.

---

## 17. Как это работает (архитектура)

```
Клиент (телефон/ноутбук)
  │  VLESS + Reality (TLS-подобный трафик)
  │  SNI = steamcommunity.com
  │  transport = TCP или XHTTP
  ▼
VPS :443 → Nginx (stream, ssl_preread)
  │
  ├── SNI = example.com (decoy)
  │     → Nginx :1443 (HTTP-сервер)
  │     → сайт-приманка
  │
  └── SNI = любой другой (steamcommunity, microsoft, ...)
        → Xray :10443 (Reality)
        → расшифровка VLESS (TCP или XHTTP)
        → запрос на целевой сайт
```

**Почему это работает:**
1. Злоумышленник сканирует ваш IP:443 — видит TLS-рукопожатие
   и валидный сертификат (Let's Encrypt). Всё выглядит как обычный сайт.
2. DPI пытается открыть соединение с доменом из SNI — видит
   легитимный сайт (decoy). Никакой подозрительной активности.
3. Ваш клиент подключается с SNI = steamcommunity.com —
   Nginx видит незнакомый SNI и отправляет трафик в Xray.
4. Xray по протоколу Reality маскирует трафик под реальное
   TLS-рукопожатие с steamcommunity.com — на проводе это
   неотличимо от настоящего Steam.

---

## 18. Известные проблемы

### 18.1. Alpine `cut` не возвращает пустую строку

**Симптом:** В config.json у всех клиентов поле `email` = UUID.

**Причина:** busybox `cut` (в Alpine) при отсутствии разделителя
возвращает всю строку, а не пустую. Исправлено в entrypoint.sh.

### 18.2. Nginx падает при старте

**Симптом:** nginx exit 1, в логах пусто.

**Причина:** `:ro` mount мешает entrypoint записать файлы.
Исправлено — самоподписанный серт генерируется в Dockerfile,
а `DECOY_HTML_DIR` монтируется без `:ro`.

### 18.3. После обновления LE сертификатов nginx отдаёт старый серт

**Причина:** file mount фиксирует inode. Используется directory mount —
Docker отслеживает имя файла при `cp`.

Подробнее: `INSTALL.md` в репозитории (англ.) или раздел 9 выше.

### 18.4. Nginx "host not found" при старте

**Причина:** nginx резолвит upstream сразу. Исправлено — добавлен
`resolver 127.0.0.11` и upstream задаётся через переменную `$backend`.

### 18.5. Разделитель клиентов — `;`, а не `,`

**Симптом:** В config.json только 1 клиент.

**Решение:** В `.env` строгая схема: `uuid1,имя1;uuid2;uuid3,имя3`.
Точка с запятой между клиентами, запятая между UUID и именем.

### 18.6. XHTTP несовместим с `flow: xtls-rprx-vision`

**Симптом:** Клиенты не подключаются, в логах xray ошибка протокола.

**Причина:** Vision — это TLS-уровневый flow, который работает только с
tcp-транспортом. XHTTP использует HTTP-мультиплексирование, где Vision
неприменим.

**Решение:** `add_user.sh` сам определяет `XRAY_NETWORK` и генерирует
правильную ссылку (без flow для XHTTP). Если правите `.env` вручную —
не указывайте flow клиентам при XHTTP.

### 18.7. XHTTP без Reality не работает через nginx ssl_preread

**Симптом:** При `security: "none"` и `network: "xhttp"` nginx не направляет
трафик, соединение падает.

**Причина:** nginx использует `ssl_preread` — читает TLS ClientHello, чтобы
определить SNI и решить, куда направить TCP-stream. Если TLS/Reality нет —
ClientHello нет, SNI не определить, nginx не знает, кому адресован трафик.

**Решение:** Не выключать `security: "reality"` при использовании XHTTP с
nginx ssl_preread. В entrypoint `security: "reality"` включён всегда — менять
не нужно.

### 18.8. `docker compose restart` не применяет новый .env

**Симптом:** После изменения `DECOY_DOMAIN` (или других переменных) в
`.env` nginx продолжает использовать старые значения (например,
`server_name example.com` вместо нового домена).

**Причина:** `docker compose restart` перезапускает контейнер с той же
конфигурацией. Env vars загружаются при `create`, а не при `start`.
`restart` не пересоздаёт контейнер.

**Решение:** Использовать `docker compose up -d` вместо `restart`.
Compose сам определяет изменения и пересоздаёт нужные контейнеры.
Либо явно: `docker compose up -d --force-recreate nginx`.

Проверить, какие env vars получил контейнер:
```bash
docker inspect nginx --format '{{.Config.Env}}'
```

### 18.9. `post_check.sh` HTTPS тест падает с 400

**Симптом:** `post_check.sh` показывает `nginx not responding on HTTPS`
и `Decoy site returned HTTP 400`.

**Причина:** Внутри контейнера `https://localhost:443` попадает в
stream-прокси (ssl_preread), а не в HTTP-сервер decoy-сайта (он на
`:1443`). Stream-блок не знает SNI=localhost и шлёт трафик в xray,
который возвращает 400.

**Решение:** Скрипт исправлен — использует `--resolve $DECOY:443:127.0.0.1`
вместо `https://localhost/`. Если правите скрипт сами — не тестируйте
HTTPS через `localhost`, всегда указывайте домен decoy.

### 18.10. fwupd жрёт 210MB RAM на Ubuntu 24.04

**Симптом:** На VPS с 1GB RAM `fwupd` (firmware update daemon) ест
~210MB RSS (21% памяти). Со временем появляется swap, падает
производительность.

**Причина:** Ubuntu 24.04 включает fwupd по умолчанию. На VPS
firmware-обновления не нужны, но сервис висит и постепенно
утекает по памяти.

**Решение:** Остановить и замаскировать:
```bash
systemctl stop fwupd
systemctl mask fwupd
```

### 18.11. `list_users.sh` давал всем клиентам одинаковый shortId

**Симптом:** У всех клиентов в VLESS-ссылке один и тот же `sid`.
Это не ошибка (Reality работает с любым shortId из списка),
но снижает diversity трафика.

**Причина:** Скрипт брал первый shortId из `XRAY_REALITY_SHORT_IDS`
и подставлял его всем клиентам.

**Решение:** Исправлено — shortId назначается round-robin по порядку
клиентов. Чтобы изменить shortId конкретному клиенту — переставьте
shortIds в `.env` или удалите лишние.

---

## 19. Где смотреть логи

| Что | Команда |
|-----|---------|
| Xray (ошибки) | `docker compose logs xray` |
| Xray (входящие соединения) | `docker compose exec xray cat /var/log/xray/access.log` |
| Nginx (доступ) | `docker compose exec nginx cat /var/log/nginx/access.log` |
| Nginx (ошибки) | `docker compose exec nginx cat /var/log/nginx/error.log` |
| Docker events | `docker events --filter 'container=xray' --filter 'container=nginx'` |

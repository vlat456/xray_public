# Changelog

## 0.3 (2026-07-23)

### Added
- XHTTP transport support — `XRAY_NETWORK`, `XRAY_XHTTP_MODE`, `XRAY_XHTTP_PATH` env vars.
- `entrypoint.sh` conditionally renders `xhttpSettings` or `tcpSettings` based on `XRAY_NETWORK`.
- `add_user.sh` reads `XRAY_NETWORK`, generates correct `type=xhttp` and omits flow for XHTTP.
- `docker-compose.yml` passes XHTTP env vars to xray container.
- `INSTALL.md`: секция 5.8 (XHTTP), таблица клиента TCP vs XHTTP, архитектура с XHTTP, known issues 18.6, 18.7.

### Changed
- `entrypoint.sh`: flow пустой при `XRAY_NETWORK=xhttp` (несовместим с Vision).

## 0.2.1 (2026-07-22)

### Changed
- `INSTALL.md`: добавлен `post_check.sh` после первого запуска и после LE.
  Пример вывода `add_user.sh` обновлён (цвета, QR). Добавлен `list_users.sh`
  в полезные команды. Диагностика: новый пункт про `post_check.sh`.
  Безопасность: рекомендация `.env` permissions.
- `post_check.sh`: рекомендация `.env` permissions изменена с `600` на `640`.

### Fixed
- `INSTALL.md`: `.env` permissions — `600` заменён на `640` с пояснением
  про владельца файла (иначе `docker compose` не прочитает).

## 0.2 (2026-07-22)

### Added
- `list_users.sh` — скрипт для просмотра пользователей. Выводит UUID, VLESS-ссылку и QR-код для каждого клиента. Цветной вывод с эмодзи.
- `post_check.sh` — comprehensive validation: system prereqs, .env sanity, Docker stack health, decoy site, Reality connectivity, systemd, SSL/certbot, security hardening.
- `add_user.sh`: рандомный shortId из списка для каждого нового пользователя (не всегда первый).
- `add_user.sh` / `list_users.sh`: QR-код для VLESS-ссылки через `api.qrserver.com`.
- `add_user.sh` / `list_users.sh`: цветной вывод с эмодзи.

### Changed
- `add-user.sh` → `add_user.sh` (consistency с `list_users.sh`). Все ссылки в документации обновлены.
- `INSTALL.md`: поле `email` заменено на человекочитаемый идентификатор (username). Имя добавляется в конец VLESS-ссылки после `#`.
- `INSTALL.md`: раздел 5.2 упрощён — `XRAY_REALITY_SERVER_NAMES` выводится из `DEST` автоматически.
- `INSTALL.md`: раздел 5.3 — добавлено ВАЖНО про уникальный shortId каждому клиенту.
- `INSTALL.md`: раздел 5.4 — инструкция начинается с "клиентов пока не добавлять, используйте add_user.sh".
- `entrypoint.sh`: если `XRAY_REALITY_SERVER_NAMES` не задан — вырезается хост из `XRAY_REALITY_DEST`.
- `.env.example`: `XRAY_REALITY_SERVER_NAMES` закомментирован. Комментарий про имя и `#`.
- `host-setup.sh`: добавлена установка python3 на хост (нужен для add_user/list_users).

### Fixed
- `add_user.sh`: `get_env_var()` переписан на Python — shell pipeline с `grep | sed | cut | xargs` обрезал последний символ из-за `["\x27"]` на macOS sed.
- `add_user.sh`: `get_env_var()` больше не глотает ошибки Python (`2>/dev/null` убран).
- `add_user.sh`: дубли `XRAY_CLIENTS=` в `.env` больше не ломают awk (первый матч заменяется, остальные удаляются). `CHANGE_ME` заменяется, а не дописывается к нему.
- `add_user.sh`: пустой `SHORT_IDS` не приводит к `random.choice([''])` (фильтр `if x`).
- `list_users.sh`: пустой `XRAY_REALITY_SERVER_NAMES` (выводится из DEST) корректно резолвится через `XRAY_REALITY_DEST`.
- `list_users.sh`: добавлена проверка наличия python3 и `.env` с понятными сообщениями.

## 0.1 (2025-??-??)

- Initial release: Xray + Reality в Docker, nginx ssl_preread, add-user.sh, host-setup.sh, INSTALL.md.

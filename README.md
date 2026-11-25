# Mushrooms — установщик 3x-ui

Интерактивный установщик для Ubuntu: поднимает панель **3x-ui** (образ **v3.8.5**).  
Если указать домен — сайт на HTTPS и VPN (VLESS + XHTTP + Reality) на порту 443.  
Если домен не указывать — только панель на порту 2053. Ставить на **чистый** сервер.

## Установка

Одна команда (Docker поставится сам, если его ещё нет):

```bash
sudo apt update && sudo apt install -y git ca-certificates curl && \
  (test -d /opt/mushrooms-src/.git || sudo git clone https://github.com/kkambucha/mushrooms.git /opt/mushrooms-src) && \
  cd /opt/mushrooms-src && sudo bash install.sh
```

Сначала переключатель сертификата: стрелки меняют вариант, Enter подтверждает, по умолчанию новый. Имеющийся — вставка fullchain, затем privkey, каждый блок завершается строкой `END`.

Дальше скрипт спросит **Config**:

- Enter — только панель.
- Вписать домен — сайт и VPN; path, UUID и остальное сгенерируются сами.
- Перенос старого клиента: после домена через пробел — страна, path, UUID, subId, пароль. Что не указать — сгенерируется.
- Пароль панели — в конце строки Config или сгенерируется (смотри `DEPLOY.txt`).
- Дождись `Done.`

Пошаговый опрос вместо одной строки: `cd /opt/mushrooms-src && USE_STEP_WIZARD=1 sudo bash install.sh`.

## Проверка

```bash
cat /opt/mushrooms/DEPLOY.txt
cd /opt/mushrooms && docker compose ps
```

- Нет `/opt/mushrooms` или нет `DEPLOY.txt` — установка не дошла до конца; смотри вывод, поправь и повтори команду.
- Панель: `http://IP:2053/` (только http; из‑за HSTS на домене лучше IP или инкогнито). Пароль — в `DEPLOY.txt`.
- Ссылка на подписку — в `DEPLOY.txt`.

## Достаточно домена

Для обычной установки хватает домена в Config. Reality-ключ установщик не спрашивает — при переносе ключей правь панель после установки.

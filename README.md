# Mushrooms — установщик 3x-ui

Интерактивный установщик для Ubuntu: поднимает панель **3x-ui** (образ **v3.8.5**).  
Если указать домен — сайт на HTTPS и VPN (VLESS + XHTTP + Reality) на порту 443.  
Если домен не указывать — только панель на порту 2053. Ставить на **чистый** сервер.

## Установка

```bash
# 1) зависимости + Docker + клон
sudo apt update && sudo apt install -y git ca-certificates curl && \
  curl -fsSL https://get.docker.com | sudo sh && \
  sudo systemctl enable --now docker && \
  docker compose version && \
  sudo git clone https://github.com/kkambucha/mushrooms.git /opt/mushrooms-src && \
  echo "OK: зависимости, Docker и клон готовы — можно запускать install.sh" || \
  echo "ERROR: что-то оборвалось на шаге 1 — смотри вывод выше, исправь и повтори"

# 2) установка
cd /opt/mushrooms-src && sudo bash install.sh
# одна строка настроек:
#   domain [country] [path] [uuid] [subId] [password]
# Enter без домена → только панель; только домен → сайт/VPN, остальное само.
# миграция: kb1.example.com Germany mypath uuid-here subidhere MyPass
# дождись Done. → /opt/mushrooms/DEPLOY.txt
```

Пошаговый визард (если нужен): `USE_STEP_WIZARD=1 sudo bash install.sh`.

## Проверка

Можно убедиться, что установка прошла:

```bash
# есть DEPLOY.txt и контейнеры Up — установка ок
cat /opt/mushrooms/DEPLOY.txt
cd /opt/mushrooms && docker compose ps
```

- Нет `/opt/mushrooms` или нет `DEPLOY.txt` — установка не дошла до конца; смотри вывод `install.sh`, поправь Docker и запусти снова.
- Панель: `http://IP:2053/` (только http; браузер иногда сам открывает https — тогда заходи по IP или в инкогнито). Логин: `admin`, пароль — в `DEPLOY.txt`.
- Ссылка на подписку и данные клиента — в `DEPLOY.txt`.

## Достаточно домена

Обычно хватает **одного доменного имени** в строке Config. Path, UUID, subId, ключи Reality, порты и т.д. **сгенерируются сами** и попадут в `DEPLOY.txt`.

В той же строке можно задать свои path/UUID/subId/страну/пароль (миграция). Reality-ключ через установщик не спрашивается — при переносе ключей правь панель после установки.

# Mushrooms — установщик 3x-ui

Интерактивный установщик для Ubuntu: поднимает панель **3x-ui** (образ **v3.8.5**).  
Если указать домен — сайт на HTTPS и VPN (VLESS + XHTTP + Reality) на порту 443.  
Если домен не указывать — только панель на порту 2053. Ставить на **чистый** сервер.

## Установка

```bash
# 1) зависимости
sudo apt update && sudo apt install -y git ca-certificates curl

# 2) Docker официальный (не ставить docker-compose-plugin через apt)
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
docker compose version   # команда должна сработать до установки

# 3) установка
git clone <YOUR_REPO_URL> /opt/mushrooms-src
cd /opt/mushrooms-src
sudo bash install.sh
# откроется визард: можно всё прокликать Enter — будет только панель;
# если ввести домен (и email для сертификата, когда спросит) — сайт и VPN
# дождись строки Done. — появится /opt/mushrooms/DEPLOY.txt
```

## Проверка

Можно убедиться, что установка прошла:

```bash
# есть DEPLOY.txt и контейнеры Up — установка ок
cat /opt/mushrooms/DEPLOY.txt
cd /opt/mushrooms && docker compose ps
```

- Нет `/opt/mushrooms` или нет `DEPLOY.txt` — установка не дошла до конца; смотри вывод `install.sh`, поправь Docker и запусти снова.
- Панель: `http://IP:2053/` (только http; браузер иногда сам открывает https — тогда заходи по IP или в инкогнито).
- Ссылка на подписку и данные клиента — в `DEPLOY.txt`.

## Достаточно домена

Обычно хватает **одного доменного имени** (и email для сертификата, если спросит). Остальное — метка клиента, путь подписки, UUID, ключи Reality, порты и т.д. — **сгенерируется само** и попадёт в `DEPLOY.txt`.

В визарде можно вручную задать свои значения (например, при переносе старого клиента). Для обычной установки **достаточно указать домен**, остальное можно оставить на Enter.

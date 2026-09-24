# Mushrooms — 3x-ui installer

Interactive installer for Ubuntu 20.04+ that deploys **3x-ui** (and optionally nginx + auto VPN inbounds).

> Not Reality/Selfsteal. FULL mode uses ordinary VLESS+TLS with certs under `/etc/3x-ui/certs/`.

## Two install modes

| Mode | When | What you get |
|------|------|----------------|
| **MINIMAL** | Leave wizard fields empty (or omit VPN fields) | Clean 3x-ui on `:2053` — configure inbounds/subscription in the panel UI |
| **FULL** | Fill domain + country + sub path + UUID + subId | Site on 443 + HTTPS subscription + TCP/WS inbounds |

## Prepare the VPS (git + Docker)

```bash
sudo apt update
sudo apt install -y git ca-certificates curl

# Official Docker (engine + compose plugin). Prefer this over distro packages.
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker

# Must succeed before install / before any docker compose commands:
docker compose version
```

**Do not** run `apt install docker-compose-plugin` unless the official Docker apt repo is already configured — Ubuntu’s default repos often return `Unable to locate package docker-compose-plugin`.

`install.sh` will also install/repair Docker via `get.docker.com` if needed.

## Install

```bash
# Clone or copy this repo (source tree):
git clone <YOUR_REPO_URL> /opt/mushrooms-src
cd /opt/mushrooms-src
sudo bash install.sh
```

Press Enter through the wizard for **MINIMAL** (clean panel). Fill all VPN fields for **FULL**.

Wait until you see `Done.` and a path to `DEPLOY.txt`.

## Source vs runtime directories

| Path | Role |
|------|------|
| `/opt/mushrooms-src` (or wherever you cloned) | Installer source (`install.sh`, templates) |
| `/opt/mushrooms` (`DEPLOY_DIR`) | Runtime: `docker-compose.yml`, certs, site, DB, `DEPLOY.txt` |

**Important:** `/opt/mushrooms` is created **only after dependencies succeed**. If install dies on Docker/compose, that directory does not exist yet — that is expected.

### Troubleshooting paths

**`cd: /opt/mushrooms: No such file or directory`**

Install did not finish past deps. Fix Docker (`docker compose version`), then:

```bash
cd /opt/mushrooms-src
sudo bash install.sh
ls /opt/mushrooms
cat /opt/mushrooms/DEPLOY.txt
```

**`no configuration file provided: not found`**

You ran `docker compose` from the **source** tree. Use the runtime dir:

```bash
cd /opt/mushrooms
docker compose ps
# or:
docker compose -f /opt/mushrooms/docker-compose.yml ps
```

**`restart nginx` fails in MINIMAL**

There is no nginx service without a domain. Use `docker compose restart 3xui` only.

## After a successful install

```bash
cd /opt/mushrooms
docker compose ps
docker compose logs -f
docker compose restart 3xui
# only if you set a domain (site/nginx installed):
docker compose restart nginx
```

- Panel admin: **`http://YOUR_IP:2053/`** (plain HTTP, root path — credentials in `DEPLOY.txt`)
- Do **not** use `https://…:2053/…/sub/…` for the admin UI — that is the subscription endpoint shape (`:2096`), not the panel
- MINIMAL: create inbounds/subscription yourself in the panel
- FULL: subscription URL and client details are in `DEPLOY.txt`

### Panel password / existing DB

Installer always resets panel username/password to wizard values via `docker exec … x-ui setting` (no need to know the old password).

**3x-ui 3.8+ CSRF:** panel rejects `POST /login` and API writes without `X-CSRF-Token`. The installer fetches `GET /csrf-token` and sends the header automatically. Manual check:

```bash
JAR=/tmp/xui.jar
TOKEN=$(curl -sS -c "$JAR" -b "$JAR" http://127.0.0.1:2053/csrf-token | jq -r .obj)
curl -sS -c "$JAR" -b "$JAR" -X POST http://127.0.0.1:2053/login \
  -H 'Content-Type: application/json' -H "X-CSRF-Token: $TOKEN" \
  -d '{"username":"admin","password":"YOUR_PASS"}'
```

If you wiped DB and ran `docker compose up` **before** finishing `install.sh`, the panel may have created its own first-boot user. Just re-run install — it will force wizard credentials. Or on the server:

```bash
cd /opt/mushrooms
docker exec mushrooms_3xui /app/x-ui setting -username admin -password 'YOUR_PASS'
docker compose restart 3xui
# then open http://YOUR_IP:2053/  and/or finish install.sh
```

Prefer letting `install.sh` finish before manually starting compose after a DB wipe.

## Wizard fields

| Prompt | Empty Enter |
|--------|-------------|
| Domain | OK → no nginx/site |
| Country, sub path, UUID, subId | OK → MINIMAL; all filled (+ domain) → FULL |
| Comment | OK |
| TCP / WS ports | Asked only in FULL (random default) |
| Panel admin user/password | Random if empty |
| Certificates | Asked only if domain set (empty → Let's Encrypt) |

## FULL mode notes

Subscription URL shape:

`https://YOUR_DOMAIN:2096/<subscription-path>/<subId>`

For client migration, enter the same domain / path / subId / UUID as the existing subscription URL; point DNS A at this VPS first.

## Security

- Panel is **HTTP** on `:2053` — strong password and/or firewall allowlist.
- Prefer restricting `:2053` / `:2096` to your admin IPs when possible.

## Layout

```
install.sh
lib/
templates/     # compose (full + 3xui-only), nginx, inbound JSON, site/
```

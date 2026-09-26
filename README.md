# Mushrooms — 3x-ui installer

Interactive installer for Ubuntu 20.04+ that deploys **3x-ui** (and optionally nginx + auto VPN inbounds).

> FULL mode = **VLESS + XHTTP + Reality selfsteal** on `:443`: the Reality target is this server's own
> nginx site on `127.0.0.1:8443` (real Let's Encrypt certificate). Anything that does not authenticate
> as a Reality client is forwarded to nginx, so from outside `:443` is an ordinary HTTPS site.
>
> 3x-ui is pinned to **v3.8.5** (Xray v26.9.9) — the version this layout was verified with.
> Always install on a **clean server**.

## Two install modes

| Mode | When | What you get |
|------|------|----------------|
| **MINIMAL** | No domain | Clean 3x-ui on `:2053` — configure inbounds/subscription in the panel UI |
| **FULL** | Domain given (everything else optional — generated when empty) | XHTTP+Reality selfsteal on 443 + site + HTTPS subscription + one client attached to all inbounds + disabled reserve TCP/WS |

Minimal FULL install: enter only the domain (and ACME email) — country, subscription path, UUID, subId, XHTTP path, Reality keys, shortIds and reserve ports are generated and written to `DEPLOY.txt`.

## FULL mode layout

| Port | Listener | Purpose |
|------|----------|---------|
| 80 | nginx | ACME webroot, everything else 301 → https |
| 443 | Xray (3x-ui) | VLESS + XHTTP + Reality; unauthenticated connections → `127.0.0.1:8443` |
| 127.0.0.1:8443 | nginx | site, TLS 1.2/1.3 + h2, LE cert — the Reality target |
| 2053 | 3x-ui | panel (HTTP) |
| 2096 | 3x-ui | HTTPS subscription |

UFW opens 22, 80, 443, 2053, 2096.

Inbounds created by the installer:

| Inbound | State | Notes |
|---------|-------|-------|
| VLESS XHTTP Reality `:443` | enabled | client from the wizard (UUID, email = country, subId, comment), flow empty, `mode auto`, `xPaddingBytes 100-1000`, fingerprint `chrome`, `xver 0` |
| VLESS TLS TCP `:<tcp port>` | **disabled**, same client attached | reserve; port closed in UFW |
| VLESS TLS WS `:<ws port>` | **disabled**, same client attached | reserve; port closed in UFW |

One client (same UUID, email, subId) is attached to all three inbounds. Disabled inbounds are expected to be left out of the subscription — check after install (`curl -s https://DOMAIN:2096/<sub-path>/<subId> | base64 -d` must show only the XHTTP link).

To use the reserve: enable the inbound in the panel → `ufw allow <port>/tcp` → clients refresh the subscription.

Why not TCP+Reality: on 2026-09-25 a correctly configured TCP+Reality selfsteal authenticated clients but traffic stopped after the first response from two Russian networks (Wi-Fi and mobile), two clients and two ports, while XHTTP+Reality with the same target worked. This matches community reports of TSPU filtering in 2026 (e.g. [XTLS/Xray-core#6293](https://github.com/XTLS/Xray-core/issues/6293)); root cause not proven.

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
| Domain | OK → MINIMAL (no nginx/site, no inbounds); filled → FULL |
| Country (client email / label) | FULL: `client` |
| Subscription path | FULL: 8 random hex |
| Client UUID | FULL: random UUID |
| subId | FULL: 16 random hex |
| Comment | OK |
| Reserve TCP / WS ports | Asked only in FULL (random default); inbounds are created disabled |
| XHTTP path | Asked only in FULL; empty → `/` + 10 random hex |
| Reality private key | Asked only in FULL; empty → new X25519 pair. Pasted key (migration) → public key is derived from it and shown before confirmation |
| Reality shortIds | Asked only in FULL; comma-separated hex (even length, 2–16); empty → 4 random |
| Panel admin user/password | Random if empty |
| Certificates | Asked only if domain set (empty → Let's Encrypt) |

## FULL mode notes

Subscription URL shape:

`https://YOUR_DOMAIN:2096/<subscription-path>/<subId>`

For client migration, enter the same domain / path / subId / UUID as the existing subscription URL (and the old Reality private key to keep `pbk` unchanged); point DNS A at this VPS first.

`DEPLOY.txt` (mode 600) contains the Reality public key, shortIds, XHTTP path and a manual `vless://` link. The private key is not written there — it lives in the panel DB and `generated/inbound-xhttp-reality.json` (mode 600).

Xray log is set to `access: none`, `loglevel: warning`. For debugging switch it in the panel (Xray settings → Log).

## Diagnostics (FULL)

```bash
ss -tlnp | grep -E ':(80|443|8443|2096)\b'     # xray on *:443, nginx on :80 and 127.0.0.1:8443
curl -I https://YOUR_DOMAIN/                   # from outside: HTTP/2 200, Let's Encrypt cert
curl -s https://YOUR_DOMAIN:2096/<sub-path>/<subId> | base64 -d   # one vless:// with type=xhttp, :443
```

Verbose logs: in the panel set Log Level `debug`, Access Log `./access.log`, restart Xray, then

```bash
docker exec mushrooms_3xui tail -F /var/log/x-ui/access.log     # "accepted ... [in-443-tcp >> direct] email: ..."
docker logs -f --since 1m mushrooms_3xui 2>&1 | grep -i reality  # "REALITY: processed invalid connection ..."
```

Note: inbounds added through the API may not appear in `/app/bin/config.json` — check with `ss`, not the file.

Server-side end-to-end test with a throwaway Xray client inside the container (replace values; stop it afterwards with `docker exec mushrooms_3xui pkill -f rt-client.json`):

```bash
cat > /tmp/rt-client.json <<'JSON'
{"inbounds":[{"listen":"127.0.0.1","port":10808,"protocol":"socks"}],
 "outbounds":[{"protocol":"vless",
   "settings":{"vnext":[{"address":"127.0.0.1","port":443,"users":[{"id":"<UUID>","encryption":"none"}]}]},
   "streamSettings":{"network":"xhttp","xhttpSettings":{"path":"<XHTTP path>","mode":"auto"},
     "security":"reality","realitySettings":{"serverName":"YOUR_DOMAIN","fingerprint":"chrome",
       "publicKey":"<public key>","shortId":"<shortId>","spiderX":"/"}}}]}
JSON
docker cp /tmp/rt-client.json mushrooms_3xui:/tmp/rt-client.json
docker exec -d mushrooms_3xui sh -c '/app/bin/xray-linux-* run -c /tmp/rt-client.json'
sleep 2; curl -sS -m 10 -x socks5h://127.0.0.1:10808 https://ifconfig.me; echo   # prints the server IP
```

## Security

- Panel is **HTTP** on `:2053` — strong password and/or firewall allowlist.
- Prefer restricting `:2053` / `:2096` to your admin IPs when possible.

## Layout

```
install.sh
lib/
lib/reality.sh # X25519 keys (openssl), shortIds, XHTTP path
templates/     # compose (full + 3xui-only), nginx, inbound JSON (xhttp-reality + reserve tcp/ws), site/
```

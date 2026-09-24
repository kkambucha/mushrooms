# Mushrooms — 3x-ui VLESS TLS installer

Interactive console installer for Ubuntu 20.04+ that deploys:

- **nginx** — static maintenance site on 80/443 (Fungi Encyclopedia page)
- **certbot** — Let's Encrypt (or paste your own PEM)
- **3x-ui** — panel on `:2053` with two VLESS+TLS inbounds (TCP + WebSocket)

> This is **not** Reality/Selfsteal. Inbounds use ordinary TLS with certificates under `/etc/3x-ui/certs/`.

## Server prerequisites

- Fresh Ubuntu 20.04+ VPS (root / sudo)
- Domain **A-record** already pointing at the VPS IP
- Outbound HTTPS (Docker Hub / ghcr.io / Let's Encrypt)

## Install

```bash
# On the VPS — copy this repo, then:
cd /path/to/mushrooms
sudo bash install.sh
```

Examples:

```bash
# scp / rsync the project, or:
git clone <YOUR_REPO_URL> /opt/mushrooms-src
cd /opt/mushrooms-src
sudo bash install.sh
```

Runtime files (compose, certs, site, DB) live in **`/opt/mushrooms`** by default (`DEPLOY_DIR`).

## Wizard prompts

| Prompt | Default |
|--------|---------|
| Domain | required |
| Country label (client email) | required |
| Subscription path name | required |
| Client UUID | required |
| Subscription ID (`subId`) | required |
| Client comment | optional (empty) |
| TCP / WS ports | random 20000–50000 |
| Panel admin user/password | random |
| Certificates | empty → Let's Encrypt; or paste PEM |

At the end the installer prints a sheet and writes `/opt/mushrooms/DEPLOY.txt`.

## Subscription URL shape

3x-ui serves subscriptions on **HTTPS port 2096** (TLS via the same domain certs):

`https://YOUR_DOMAIN:2096/<subscription-path>/<subId>`

The wizard “subscription path name” is the middle segment. Panel UI stays on `:2053`.

### Migrating existing clients

Enter the **same** Domain, subscription path, and `subId` as in the URL already configured on clients (and the same client UUID if you want the same profile). Point DNS A at the new VPS first. Clients keep the old subscription URL; a refresh pulls new VLESS links (new ports) with no client-side URL change.

## After install

- Site: `https://YOUR_DOMAIN/`
- Panel: `http://YOUR_DOMAIN:2053` (credentials in `DEPLOY.txt`)
- Subscription URL: printed in `DEPLOY.txt`

Replace the maintenance page anytime:

```bash
nano /opt/mushrooms/site/index.html
# no restart needed for static HTML; or:
cd /opt/mushrooms && docker compose restart nginx
```

## Security notes

- Panel listens publicly on **HTTP :2053**. Protect with a strong password and/or firewall IP allowlist.
- Prefer restricting `:2053` and `:2096` in UFW to your admin IPs when possible.

## Layout

```
install.sh
lib/           # bash modules
templates/     # compose, nginx, inbound JSON, site/
```

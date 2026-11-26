```bash
sudo apt update && sudo apt install -y git ca-certificates curl && \
  (test -d /opt/mushrooms-src/.git || sudo git clone https://github.com/kkambucha/mushrooms.git /opt/mushrooms-src) && \
  cd /opt/mushrooms-src && sudo bash install.sh
```

```text
domain [country] [path] [uuid] [subId] [password] [certs]
```

```bash
cat /opt/mushrooms/DEPLOY.txt
cd /opt/mushrooms && docker compose ps
```

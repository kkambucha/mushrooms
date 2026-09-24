#!/usr/bin/env bash
# Prepare deploy directory, nginx config, docker compose, start stack

prepare_deploy_dir() {
  log "Preparing deploy directory ${DEPLOY_DIR}"
  mkdir -p \
    "${DEPLOY_DIR}/nginx" \
    "${DEPLOY_DIR}/site" \
    "${DEPLOY_DIR}/certs" \
    "${DEPLOY_DIR}/certbot/www" \
    "${DEPLOY_DIR}/data/db" \
    "${DEPLOY_DIR}/generated"

  # Copy static site
  cp -a "${REPO_DIR}/templates/site/." "${DEPLOY_DIR}/site/"

  # Compose file
  cp "${REPO_DIR}/templates/docker-compose.yml.tpl" "${DEPLOY_DIR}/docker-compose.yml"
}

build_nginx_http_only() {
  local http_root='root /var/www/html; try_files $uri $uri/ /index.html;'
  local https_block='# HTTPS not yet enabled'
  render_nginx "$http_root" "$https_block"
}

build_nginx_https() {
  local http_root='return 301 https://$host$request_uri;'
  local https_block
  https_block="$(cat <<EOF
    server {
        listen 443 ssl;
        listen [::]:443 ssl;
        http2 on;
        server_name ${DOMAIN};

        ssl_certificate     /etc/nginx/certs/fullchain.pem;
        ssl_certificate_key /etc/nginx/certs/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;

        root /var/www/html;
        index index.html;

        location / {
            try_files \$uri \$uri/ /index.html;
        }
    }
EOF
)"
  render_nginx "$http_root" "$https_block"
}

render_nginx() {
  local http_root="$1"
  local https_block="$2"
  local tpl="${REPO_DIR}/templates/nginx.conf.tpl"
  local out="${DEPLOY_DIR}/nginx/nginx.conf"
  local https_file
  https_file="$(mktemp)"
  printf '%s\n' "$https_block" >"$https_file"

  sed \
    -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__HTTP_ROOT__|${http_root}|g" \
    "$tpl" | awk -v f="$https_file" '
      /__HTTPS_SERVER__/ {
        while ((getline line < f) > 0) print line
        close(f)
        next
      }
      { print }
    ' >"$out"

  rm -f "$https_file"
}

compose_up() {
  log "Starting Docker Compose"
  cd "${DEPLOY_DIR}"
  docker compose pull
  docker compose up -d
}

compose_restart_nginx() {
  cd "${DEPLOY_DIR}"
  docker compose up -d nginx
  docker compose restart nginx
}

wait_for_panel() {
  log "Waiting for 3x-ui panel on :2053"
  local i code
  for i in $(seq 1 90); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 "http://127.0.0.1:2053/" 2>/dev/null || true)"
    if [[ "$code" =~ ^[0-9]{3}$ && "$code" != "000" ]]; then
      log "Panel is responding (HTTP ${code})"
      sleep 2
      return 0
    fi
    sleep 2
  done
  die "3x-ui panel did not become ready on port 2053"
}

stop_conflicting_web() {
  # Free 80/443 if system nginx/apache is running
  if systemctl is-active --quiet nginx 2>/dev/null; then
    warn "Stopping system nginx to free ports 80/443"
    systemctl stop nginx || true
    systemctl disable nginx || true
  fi
  if systemctl is-active --quiet apache2 2>/dev/null; then
    warn "Stopping system apache2 to free ports 80/443"
    systemctl stop apache2 || true
    systemctl disable apache2 || true
  fi
}

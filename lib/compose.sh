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

  cp -a "${REPO_DIR}/templates/site/." "${DEPLOY_DIR}/site/"

  if [[ "${ENABLE_SITE:-false}" == "true" ]]; then
    cp "${REPO_DIR}/templates/docker-compose.yml.tpl" "${DEPLOY_DIR}/docker-compose.yml"
  else
    # Clean panel only — no nginx service
    cp "${REPO_DIR}/templates/docker-compose.3xui-only.yml.tpl" "${DEPLOY_DIR}/docker-compose.yml"
    # Placeholder certs dir so the volume mount exists
    if [[ ! -f "${DEPLOY_DIR}/certs/fullchain.pem" ]]; then
      openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout "${DEPLOY_DIR}/certs/privkey.pem" \
        -out "${DEPLOY_DIR}/certs/fullchain.pem" \
        -subj "/CN=localhost" >/dev/null 2>&1 || true
      chmod 644 "${DEPLOY_DIR}/certs/fullchain.pem" 2>/dev/null || true
      chmod 600 "${DEPLOY_DIR}/certs/privkey.pem" 2>/dev/null || true
    fi
  fi

  log "Deploy directory ready: ${DEPLOY_DIR}"
}

build_nginx_http_only() {
  local http_root='root /var/www/html; try_files $uri $uri/ /index.html;'
  local https_block='# HTTPS not yet enabled'
  render_nginx "$http_root" "$https_block"
}

# build_nginx_https — site only on 127.0.0.1:8443, it is the Reality target;
# public :443 belongs to Xray (VLESS XHTTP + Reality). Used only when a domain is set (FULL).
build_nginx_https() {
  local http_root='return 301 https://$host$request_uri;'
  local listen_lines='        listen 127.0.0.1:8443 ssl;'
  local https_block
  https_block="$(cat <<EOF
    server {
${listen_lines}
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
  log "Starting Docker Compose in ${DEPLOY_DIR}"
  cd "${DEPLOY_DIR}"
  docker compose pull
  # Drop services removed from compose (e.g. nginx after downgrade to MINIMAL)
  docker compose up -d --remove-orphans
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

# Die if anything already listens on TCP port $1 (Xray must bind it)
ensure_port_free() {
  local port="$1" line
  line="$(ss -Htlnp "( sport = :${port} )" 2>/dev/null | head -n1 || true)"
  if [[ -n "$line" ]]; then
    die "Port ${port} is already in use: ${line}
Stop that service (or remove its config) and re-run on a clean server."
  fi
}

stop_conflicting_web() {
  if [[ "${ENABLE_SITE:-false}" != "true" ]]; then
    return 0
  fi
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

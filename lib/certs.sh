#!/usr/bin/env bash
# Certificate handling: paste PEM or Let's Encrypt via webroot

write_pasted_certs() {
  log "Writing pasted certificates"
  mkdir -p "${DEPLOY_DIR}/certs"
  printf '%s' "$FULLCHAIN_PEM" >"${DEPLOY_DIR}/certs/fullchain.pem"
  printf '%s' "$PRIVKEY_PEM" >"${DEPLOY_DIR}/certs/privkey.pem"
  chmod 644 "${DEPLOY_DIR}/certs/fullchain.pem"
  chmod 600 "${DEPLOY_DIR}/certs/privkey.pem"
}

write_self_signed_placeholder() {
  # Temporary cert so nginx can start with HTTPS block if needed; replaced by LE
  log "Generating temporary self-signed certificate"
  mkdir -p "${DEPLOY_DIR}/certs"
  openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
    -keyout "${DEPLOY_DIR}/certs/privkey.pem" \
    -out "${DEPLOY_DIR}/certs/fullchain.pem" \
    -subj "/CN=${DOMAIN}" >/dev/null 2>&1
  chmod 644 "${DEPLOY_DIR}/certs/fullchain.pem"
  chmod 600 "${DEPLOY_DIR}/certs/privkey.pem"
}

issue_letsencrypt() {
  log "Issuing Let's Encrypt certificate for ${DOMAIN}"
  mkdir -p "${DEPLOY_DIR}/certbot/www" "${DEPLOY_DIR}/certbot/logs" "${DEPLOY_DIR}/certs"
  mkdir -p "${DEPLOY_DIR}/certbot/config/renewal-hooks/deploy"

  # nginx must already serve /.well-known/acme-challenge from certbot/www
  certbot certonly \
    --webroot \
    -w "${DEPLOY_DIR}/certbot/www" \
    -d "${DOMAIN}" \
    --email "${ACME_EMAIL}" \
    --agree-tos \
    --non-interactive \
    --keep-until-expiring \
    --logs-dir "${DEPLOY_DIR}/certbot/logs" \
    --config-dir "${DEPLOY_DIR}/certbot/config" \
    --work-dir "${DEPLOY_DIR}/certbot/work"

  local live="${DEPLOY_DIR}/certbot/config/live/${DOMAIN}"
  [[ -f "${live}/fullchain.pem" ]] || die "certbot did not produce fullchain.pem"
  [[ -f "${live}/privkey.pem" ]] || die "certbot did not produce privkey.pem"

  cp -L "${live}/fullchain.pem" "${DEPLOY_DIR}/certs/fullchain.pem"
  cp -L "${live}/privkey.pem" "${DEPLOY_DIR}/certs/privkey.pem"
  chmod 644 "${DEPLOY_DIR}/certs/fullchain.pem"
  chmod 600 "${DEPLOY_DIR}/certs/privkey.pem"
}

install_cert_renew_hook() {
  log "Installing certbot renew deploy hook (under custom config-dir)"
  # Certbot only runs hooks from the active --config-dir, not /etc/letsencrypt
  local hook_dir="${DEPLOY_DIR}/certbot/config/renewal-hooks/deploy"
  mkdir -p "$hook_dir"
  cat >"${hook_dir}/mushrooms-reload.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
LIVE="${DEPLOY_DIR}/certbot/config/live/${DOMAIN}"
DEST="${DEPLOY_DIR}/certs"
if [[ -f "\${LIVE}/fullchain.pem" ]]; then
  cp -L "\${LIVE}/fullchain.pem" "\${DEST}/fullchain.pem"
  cp -L "\${LIVE}/privkey.pem" "\${DEST}/privkey.pem"
  chmod 644 "\${DEST}/fullchain.pem"
  chmod 600 "\${DEST}/privkey.pem"
  cd "${DEPLOY_DIR}" && docker compose restart nginx 3xui || true
fi
EOF
  chmod +x "${hook_dir}/mushrooms-reload.sh"

  cat >/etc/cron.d/mushrooms-certbot <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 3 * * * root certbot renew --config-dir ${DEPLOY_DIR}/certbot/config --work-dir ${DEPLOY_DIR}/certbot/work --logs-dir ${DEPLOY_DIR}/certbot/logs --quiet
EOF
}

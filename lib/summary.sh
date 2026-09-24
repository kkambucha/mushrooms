#!/usr/bin/env bash
# Print and save deployment summary

write_summary() {
  compute_subscription_url
  local site_url panel_url out
  site_url="https://${DOMAIN}/"
  panel_url="http://${DOMAIN}:2053"
  out="${DEPLOY_DIR}/DEPLOY.txt"

  cat >"$out" <<EOF
════════════════════════════════════════════════════════════
 Mushrooms / 3x-ui deployment summary
 Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
════════════════════════════════════════════════════════════

SITE
  URL:            ${site_url}
  Files:          ${DEPLOY_DIR}/site/

PANEL (keep credentials private)
  URL:            ${panel_url}
  Also:           http://${PUBLIC_IP:-<server-ip>}:2053
  Username:       ${ADMIN_USER}
  Password:       ${ADMIN_PASS}
  WARNING:        Panel is HTTP on :2053 — use a strong password / restrict by firewall if needed.

SUBSCRIPTION
  URL:            ${SUBSCRIPTION_URL}
  Path name:      /${SUB_PATH}/
  SubId:          ${SUB_ID}
  Sub port:       2096

CLIENT
  Email/label:    ${COUNTRY}
  UUID:           ${CLIENT_UUID}
  Comment:        ${COMMENT:--}

INBOUNDS
  VLESS TCP TLS:  ${DOMAIN}:${TCP_PORT}  (remark: ${COUNTRY} TCP)
  VLESS WS TLS:   ${DOMAIN}:${WS_PORT}   (remark: ${COUNTRY} WS, path /)
  Certs:          ${DEPLOY_DIR}/certs/fullchain.pem
                  ${DEPLOY_DIR}/certs/privkey.pem
                  (mounted in panel as /etc/3x-ui/certs/)

SERVER
  Deploy dir:     ${DEPLOY_DIR}
  Public IP:      ${PUBLIC_IP:-unknown}
  Compose:        cd ${DEPLOY_DIR} && docker compose ps

CERT RENEWAL
  Mode:           ${CERT_MODE}
  Manual renew:   certbot renew --config-dir ${DEPLOY_DIR}/certbot/config --work-dir ${DEPLOY_DIR}/certbot/work --logs-dir ${DEPLOY_DIR}/certbot/logs
  Cron:           /etc/cron.d/mushrooms-certbot (if certbot mode)

USEFUL COMMANDS
  docker compose -f ${DEPLOY_DIR}/docker-compose.yml logs -f
  docker compose -f ${DEPLOY_DIR}/docker-compose.yml restart
  ufw status

════════════════════════════════════════════════════════════
EOF

  echo
  cat "$out"
  echo
  chmod 600 "$out"
  log "Summary saved to ${out} (mode 600)"
}

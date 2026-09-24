#!/usr/bin/env bash
# Print and save deployment summary

write_summary() {
  local panel_host out
  panel_host="${DOMAIN:-${PUBLIC_IP:-<server-ip>}}"
  out="${DEPLOY_DIR}/DEPLOY.txt"

  if [[ "${INSTALL_MODE}" == "full" ]]; then
    compute_subscription_url
  else
    SUBSCRIPTION_URL="(configure in panel UI)"
  fi

  {
    cat <<EOF
════════════════════════════════════════════════════════════
 Mushrooms / 3x-ui deployment summary
 Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
 Mode:      ${INSTALL_MODE}
════════════════════════════════════════════════════════════

DEPLOY DIRECTORY (runtime — use this for docker compose)
  Path:           ${DEPLOY_DIR}
  Compose file:   ${DEPLOY_DIR}/docker-compose.yml
  This file:      ${out}

  Source code (install.sh) is separate — e.g. /opt/mushrooms-src
  /opt/mushrooms exists only AFTER a successful install past dependencies.

PANEL (keep credentials private)
  URL:            http://${panel_host}:2053
  Also:           http://${PUBLIC_IP:-<server-ip>}:2053
  Username:       ${ADMIN_USER}
  Password:       ${ADMIN_PASS}
  WARNING:        Panel is HTTP on :2053 — use a strong password / restrict by firewall if needed.

EOF

    if [[ "${ENABLE_SITE}" == "true" ]]; then
      cat <<EOF
SITE
  URL:            https://${DOMAIN}/
  Files:          ${DEPLOY_DIR}/site/
  Cert mode:      ${CERT_MODE}

EOF
    else
      cat <<EOF
SITE
  (not installed — no domain given; nginx service not running)

EOF
    fi

    if [[ "${INSTALL_MODE}" == "full" ]]; then
      cat <<EOF
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

EOF
    else
      cat <<EOF
VPN / SUBSCRIPTION
  Not auto-configured. Open the panel and create inbounds / subscription yourself.

EOF
    fi

    cat <<EOF
SERVER
  Public IP:      ${PUBLIC_IP:-unknown}
  Install mode:   ${INSTALL_MODE}

CERT RENEWAL
EOF
    if [[ "${CERT_MODE}" == "certbot" ]]; then
      cat <<EOF
  Mode:           certbot
  Manual renew:   certbot renew --config-dir ${DEPLOY_DIR}/certbot/config --work-dir ${DEPLOY_DIR}/certbot/work --logs-dir ${DEPLOY_DIR}/certbot/logs
  Cron:           /etc/cron.d/mushrooms-certbot
EOF
    else
      cat <<EOF
  Mode:           ${CERT_MODE}
EOF
    fi

    cat <<EOF

USEFUL COMMANDS (always from deploy dir or with -f)
  cd ${DEPLOY_DIR}
  docker compose ps
  docker compose logs -f
  docker compose restart 3xui
EOF
    if [[ "${ENABLE_SITE}" == "true" ]]; then
      cat <<EOF
  docker compose restart nginx
EOF
    fi
    cat <<EOF
  # or from anywhere:
  docker compose -f ${DEPLOY_DIR}/docker-compose.yml ps
  ufw status

════════════════════════════════════════════════════════════
EOF
  } >"$out"

  echo
  cat "$out"
  echo
  chmod 600 "$out"
  log "Deploy directory: ${DEPLOY_DIR}"
  log "Summary saved to ${out} (mode 600)"
}

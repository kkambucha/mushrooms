#!/usr/bin/env bash
# Interactive wizard — populates CONFIG_* / shared env vars

ask_config() {
  log "Configuration wizard"
  echo "Fields marked (required) have no defaults — enter a value."
  echo "DNS A-record for the domain should already point to this VPS."
  echo "For seamless client migration, enter Domain / subscription path / subId"
  echo "exactly as in the existing URL: https://DOMAIN:2096/PATH/SUB_ID"
  echo

  prompt "Domain name (required)" ""
  DOMAIN="${REPLY}"
  [[ -n "$DOMAIN" ]] || die "Domain is required"
  DOMAIN="${DOMAIN,,}"
  DOMAIN="${DOMAIN#https://}"
  DOMAIN="${DOMAIN#http://}"
  DOMAIN="${DOMAIN%%/*}"

  prompt "Country / client email label (required)" ""
  COUNTRY="${REPLY}"
  [[ -n "$COUNTRY" ]] || die "Country / client email label is required"

  prompt "Subscription path name (required)" ""
  SUB_PATH="${REPLY}"
  [[ -n "$SUB_PATH" ]] || die "Subscription path name is required"
  # normalize: strip leading/trailing slashes
  SUB_PATH="${SUB_PATH#/}"
  SUB_PATH="${SUB_PATH%/}"
  [[ -n "$SUB_PATH" ]] || die "Subscription path name is required"

  prompt "Client UUID (required)" ""
  CLIENT_UUID="${REPLY}"
  [[ -n "$CLIENT_UUID" ]] || die "Client UUID is required"
  if [[ ! "$CLIENT_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    die "Client UUID must look like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  fi

  prompt "Subscription ID / subId (required)" ""
  SUB_ID="${REPLY}"
  [[ -n "$SUB_ID" ]] || die "Subscription ID is required"

  prompt "Client comment (optional)" ""
  COMMENT="${REPLY}"

  local tcp ws
  tcp="$(rand_port)"
  ws="$(rand_port)"
  while [[ "$ws" -eq "$tcp" ]]; do
    ws="$(rand_port)"
  done
  prompt "VLESS TCP TLS port" "$tcp"
  TCP_PORT="${REPLY}"
  prompt "VLESS WS TLS port" "$ws"
  WS_PORT="${REPLY}"
  [[ "$TCP_PORT" != "$WS_PORT" ]] || die "TCP and WS ports must differ"

  local gen_user gen_pass
  gen_user="admin_$(rand_alnum 6)"
  gen_pass="$(rand_password)"
  prompt "Panel admin username" "$gen_user"
  ADMIN_USER="${REPLY}"
  prompt_secret "Panel admin password" "$gen_pass"
  ADMIN_PASS="${REPLY}"

  echo
  echo "TLS certificates for ${DOMAIN}"
  echo "  - Paste fullchain + privkey (type END after each), OR"
  echo "  - Leave empty to issue via Let's Encrypt (certbot)"
  echo

  CERT_MODE="certbot"
  FULLCHAIN_PEM=""
  PRIVKEY_PEM=""

  prompt_multiline_pem "Fullchain certificate (fullchain.pem)" "END CERTIFICATE"
  if [[ -n "${REPLY}" ]]; then
    FULLCHAIN_PEM="${REPLY}"
    prompt_multiline_pem "Private key (privkey.pem)" "END PRIVATE KEY"
    [[ -n "${REPLY}" ]] || die "Private key required when fullchain is provided"
    PRIVKEY_PEM="${REPLY}"
    CERT_MODE="paste"
  else
    prompt "Email for Let's Encrypt" ""
    ACME_EMAIL="${REPLY}"
    [[ -n "$ACME_EMAIL" ]] || die "ACME email required when certificates are not pasted"
  fi

  PUBLIC_IP="$(detect_public_ip)"
  echo
  log "Summary of choices"
  echo "  Domain:        $DOMAIN"
  echo "  Public IP:     ${PUBLIC_IP:-unknown}"
  echo "  Country:       $COUNTRY"
  echo "  Sub path:      /$SUB_PATH"
  echo "  UUID:          $CLIENT_UUID"
  echo "  SubId:         $SUB_ID"
  echo "  TCP port:      $TCP_PORT"
  echo "  WS port:       $WS_PORT"
  echo "  Panel user:    $ADMIN_USER"
  echo "  Cert mode:     $CERT_MODE"
  echo
  prompt "Proceed with installation?" "yes"
  [[ "${REPLY,,}" == "yes" || "${REPLY,,}" == "y" ]] || die "Aborted by user"

  # DNS soft check
  if command -v getent >/dev/null 2>&1 && [[ -n "$PUBLIC_IP" ]]; then
    local resolved
    resolved="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [[ -n "$resolved" && "$resolved" != "$PUBLIC_IP" ]]; then
      warn "DNS for $DOMAIN resolves to $resolved, this host is $PUBLIC_IP — certbot may fail"
    fi
  fi
}

#!/usr/bin/env bash
# Interactive wizard — populates CONFIG_* / shared env vars

ask_config() {
  log "Configuration wizard"
  echo "Domain given → FULL: VLESS XHTTP + Reality on :443 + site + HTTPS subscription."
  echo "  Optional: country, sub path, UUID, subId (for migration). Everything else is generated."
  echo "No domain → MINIMAL: clean 3x-ui panel only."
  echo "Runtime will be created at ${DEPLOY_DIR} after dependencies succeed."
  echo

  INSTALL_MODE="minimal"
  ENABLE_SITE="false"
  DOMAIN=""
  COUNTRY=""
  SUB_PATH=""
  CLIENT_UUID=""
  SUB_ID=""
  COMMENT=""
  TCP_PORT=""
  WS_PORT=""
  XHTTP_PATH=""
  REALITY_PRIVATE_KEY=""
  REALITY_PUBLIC_KEY=""
  REALITY_SHORT_IDS_JSON=""
  REALITY_SHORT_ID=""
  REALITY_KEY_SOURCE=""
  CERT_MODE="none"
  FULLCHAIN_PEM=""
  PRIVKEY_PEM=""
  ACME_EMAIL=""

  prompt "Domain name (optional)" ""
  DOMAIN="${REPLY}"
  if [[ -n "$DOMAIN" ]]; then
    DOMAIN="${DOMAIN,,}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN%%/*}"
    ENABLE_SITE="true"
    ACME_EMAIL="example@gmail.com"
  fi

  prompt "Country / client email label (optional, default: client)" ""
  COUNTRY="${REPLY}"

  prompt "Subscription path name (optional, auto if empty)" ""
  SUB_PATH="${REPLY}"
  SUB_PATH="${SUB_PATH#/}"
  SUB_PATH="${SUB_PATH%/}"

  prompt "Client UUID (optional, auto if empty)" ""
  CLIENT_UUID="${REPLY}"
  if [[ -n "$CLIENT_UUID" ]]; then
    if [[ ! "$CLIENT_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
      die "Client UUID must look like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    fi
  fi

  prompt "Subscription ID / subId (optional, auto if empty)" ""
  SUB_ID="${REPLY}"

  GENERATED_FIELDS=()
  if [[ -n "$DOMAIN" ]]; then
    INSTALL_MODE="full"
    if [[ -z "$COUNTRY" ]]; then
      COUNTRY="client"
      GENERATED_FIELDS+=("country")
    fi
    if [[ -z "$SUB_PATH" ]]; then
      SUB_PATH="$(rand_hex 8)"
      GENERATED_FIELDS+=("sub path")
    fi
    if [[ -z "$CLIENT_UUID" ]]; then
      CLIENT_UUID="$(rand_uuid)"
      GENERATED_FIELDS+=("UUID")
    fi
    if [[ -z "$SUB_ID" ]]; then
      SUB_ID="$(rand_hex 16)"
      GENERATED_FIELDS+=("subId")
    fi
  else
    INSTALL_MODE="minimal"
    if [[ -n "$COUNTRY" || -n "$SUB_PATH" || -n "$CLIENT_UUID" || -n "$SUB_ID" ]]; then
      warn "No domain — using MINIMAL mode; country/sub path/UUID/subId are ignored."
      warn "Reality selfsteal needs a domain (site + Let's Encrypt certificate)."
    fi
  fi

  if [[ "$INSTALL_MODE" == "full" ]]; then
    local tcp ws
    tcp="$(rand_port)"
    ws="$(rand_port)"
    while [[ "$ws" -eq "$tcp" ]]; do
      ws="$(rand_port)"
    done
    TCP_PORT="$tcp"
    WS_PORT="$ws"
    GENERATED_FIELDS+=("TCP port" "WS port")

    XHTTP_PATH="/$(rand_hex 10)"
    GENERATED_FIELDS+=("XHTTP path")
    reality_validate_path "$XHTTP_PATH" || die "XHTTP path may contain only A-Z a-z 0-9 . _ ~ / -"

    reality_generate_keypair
    REALITY_KEY_SOURCE="generated"
    GENERATED_FIELDS+=("Reality keys")

    reality_generate_short_ids
    GENERATED_FIELDS+=("shortIds")

    CERT_MODE="certbot"
  fi

  ADMIN_USER="admin"
  local gen_pass
  gen_pass="$(rand_password)"
  prompt_secret "Panel admin password" "$gen_pass"
  ADMIN_PASS="${REPLY}"

  PUBLIC_IP="$(detect_public_ip)"
  echo
  log "Summary of choices"
  echo "  Install mode: ${INSTALL_MODE}"
  echo "  Deploy dir:   ${DEPLOY_DIR} (created after deps succeed)"
  echo "  Domain:       ${DOMAIN:-"(none — no nginx site)"}"
  echo "  Public IP:    ${PUBLIC_IP:-unknown}"
  echo "  Site/nginx:   ${ENABLE_SITE}"
  if [[ "$INSTALL_MODE" == "full" ]]; then
    _gen() { [[ " ${GENERATED_FIELDS[*]:-} " == *" $1 "* ]] && printf ' (generated)'; true; }
    echo "  Country:      ${COUNTRY}$(_gen country)"
    echo "  Sub path:     /${SUB_PATH}$(_gen 'sub path')"
    echo "  UUID:         ${CLIENT_UUID}$(_gen UUID)"
    echo "  SubId:        ${SUB_ID}$(_gen subId)"
    echo "  Main inbound: VLESS XHTTP + Reality :443 → target 127.0.0.1:8443"
    echo "  XHTTP path:   $XHTTP_PATH"
    echo "  Reality pbk:  $REALITY_PUBLIC_KEY (private key ${REALITY_KEY_SOURCE})"
    echo "  shortIds:     $(jq -r 'join(", ")' <<<"$REALITY_SHORT_IDS_JSON")"
    echo "  Reserve TCP:  $TCP_PORT (disabled in panel, UFW open)"
    echo "  Reserve WS:   $WS_PORT (enabled in panel, UFW open)"
    echo "  ACME email:   ${ACME_EMAIL}"
  else
    echo "  VPN auto:     skipped — configure inbounds/subscription in the panel UI"
  fi
  echo "  Panel user:   $ADMIN_USER"
  echo "  Cert mode:    $CERT_MODE"
  echo
  prompt "Proceed with installation?" "yes"
  [[ "${REPLY,,}" == "yes" || "${REPLY,,}" == "y" ]] || die "Aborted by user"

  if [[ "$ENABLE_SITE" == "true" ]] && command -v getent >/dev/null 2>&1 && [[ -n "$PUBLIC_IP" ]]; then
    local resolved
    resolved="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [[ -n "$resolved" && "$resolved" != "$PUBLIC_IP" ]]; then
      warn "DNS for $DOMAIN resolves to $resolved, this host is $PUBLIC_IP — certbot may fail"
    fi
  fi
}

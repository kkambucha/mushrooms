#!/usr/bin/env bash
# Interactive wizard — populates CONFIG_* / shared env vars

ask_config() {
  log "Configuration wizard"
  echo "Domain given → FULL: VLESS XHTTP + Reality selfsteal on :443 + site + HTTPS subscription."
  echo "  Every other field is optional — empty ones are generated automatically."
  echo "No domain → MINIMAL: clean 3x-ui panel only (configure VPN later in the UI)."
  echo "Runtime will be created at ${DEPLOY_DIR} after dependencies succeed."
  echo "Migration tip: enter the existing country/sub path/UUID/subId (and Reality private key)"
  echo "  to keep current client links working."
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

  prompt "Client comment (optional)" ""
  COMMENT="${REPLY}"

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
    echo
    echo "Main inbound: VLESS + XHTTP + Reality on :443 (target: site on 127.0.0.1:8443)."
    echo "Reserve inbounds VLESS TLS TCP/WS: created DISABLED, client attached, ports closed in UFW."
    prompt "Reserve VLESS TCP TLS port (disabled)" "$tcp"
    TCP_PORT="${REPLY}"
    prompt "Reserve VLESS WS TLS port (disabled)" "$ws"
    WS_PORT="${REPLY}"
    local p
    for p in "$TCP_PORT" "$WS_PORT"; do
      [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 )) || die "Invalid port: ${p}"
      case "$p" in
        80|443|2053|2096|8443) die "Port ${p} is reserved (80, 443, 2053, 2096, 8443)" ;;
      esac
    done
    [[ "$TCP_PORT" != "$WS_PORT" ]] || die "TCP and WS ports must differ"

    local def_path
    def_path="/$(rand_hex 10)"
    prompt "XHTTP path" "$def_path"
    XHTTP_PATH="${REPLY}"
    [[ "$XHTTP_PATH" == /* ]] || XHTTP_PATH="/${XHTTP_PATH}"
    reality_validate_path "$XHTTP_PATH" || die "XHTTP path may contain only A-Z a-z 0-9 . _ ~ / -"

    echo "Reality private key: paste an existing one (migration) or leave empty to generate."
    prompt_secret "Reality private key (optional)" ""
    if [[ -n "${REPLY}" ]]; then
      REALITY_PRIVATE_KEY="${REPLY//[[:space:]]/}"
      reality_validate_private "$REALITY_PRIVATE_KEY" \
        || die "Reality private key must be 43 base64url chars (32 bytes)"
      reality_derive_public "$REALITY_PRIVATE_KEY"
      REALITY_KEY_SOURCE="pasted"
    else
      reality_generate_keypair
      REALITY_KEY_SOURCE="generated"
    fi

    prompt "Reality shortIds, comma-separated (optional)" ""
    if [[ -n "${REPLY}" ]]; then
      reality_parse_short_ids "${REPLY}"
    else
      reality_generate_short_ids
    fi
  fi

  local gen_user gen_pass
  gen_user="admin_$(rand_alnum 6)"
  gen_pass="$(rand_password)"
  prompt "Panel admin username" "$gen_user"
  ADMIN_USER="${REPLY}"
  prompt_secret "Panel admin password" "$gen_pass"
  ADMIN_PASS="${REPLY}"

  if [[ "$ENABLE_SITE" == "true" ]]; then
    echo
    echo "TLS certificates for ${DOMAIN}"
    echo "  - Paste fullchain + privkey (type END after each), OR"
    echo "  - Leave empty to issue via Let's Encrypt (certbot)"
    echo

    CERT_MODE="certbot"
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
  fi

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
    echo "  Reserve TCP:  $TCP_PORT (disabled, client attached, port closed)"
    echo "  Reserve WS:   $WS_PORT (disabled, client attached, port closed)"
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

#!/usr/bin/env bash
# Interactive config — default: one line; step wizard: USE_STEP_WIZARD=1

# Reset shared config vars to empty defaults
_ask_init_vars() {
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
  ADMIN_USER="admin"
  ADMIN_PASS=""
  GENERATED_FIELDS=()
}

# Normalize DOMAIN string; set ENABLE_SITE + ACME if non-empty
_ask_normalize_domain() {
  if [[ -n "$DOMAIN" ]]; then
    DOMAIN="${DOMAIN,,}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN%%/*}"
    ENABLE_SITE="true"
    ACME_EMAIL="example@gmail.com"
  fi
}

# After DOMAIN/COUNTRY/SUB_PATH/CLIENT_UUID/SUB_ID are set: modes + auto-fill + Reality/ports
_ask_apply_domain_mode() {
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
    if [[ "$CERT_MODE" == "paste" ]]; then
      warn "No domain — pasted certificate is ignored."
      CERT_MODE="none"
      FULLCHAIN_PEM=""
      PRIVKEY_PEM=""
    fi
    if [[ -n "$COUNTRY" || -n "$SUB_PATH" || -n "$CLIENT_UUID" || -n "$SUB_ID" ]]; then
      warn "No domain — using MINIMAL mode; country/sub path/UUID/subId are ignored."
      warn "Reality selfsteal needs a domain (site + Let's Encrypt certificate)."
    fi
  fi

  if [[ "$INSTALL_MODE" == "full" ]]; then
    _ask_finish_full_defaults
  fi
}

_ask_finish_full_defaults() {
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

  if [[ "$CERT_MODE" != "paste" ]]; then
    CERT_MODE="certbot"
  fi
}

_ask_validate_uuid_if_set() {
  if [[ -n "$CLIENT_UUID" ]]; then
    if [[ ! "$CLIENT_UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
      die "Client UUID must look like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    fi
  fi
}

_ask_ensure_admin_password() {
  if [[ -z "$ADMIN_PASS" ]]; then
    ADMIN_PASS="$(rand_password)"
    GENERATED_FIELDS+=("panel password")
  fi
}

_ask_summary_and_proceed() {
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
  if [[ " ${GENERATED_FIELDS[*]:-} " == *" panel password "* ]]; then
    echo "  Panel pass:   (generated — see DEPLOY.txt)"
  else
    echo "  Panel pass:   (provided — see DEPLOY.txt)"
  fi
  echo "  Cert mode:    $CERT_MODE"
  echo
  prompt "Proceed with installation?" "yes"
  [[ "${REPLY,,}" == "yes" || "${REPLY,,}" == "y" ]] || die "Aborted by user"

  if [[ "$ENABLE_SITE" == "true" && "$CERT_MODE" == "certbot" ]] && command -v getent >/dev/null 2>&1 && [[ -n "$PUBLIC_IP" ]]; then
    local resolved
    resolved="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [[ -n "$resolved" && "$resolved" != "$PUBLIC_IP" ]]; then
      warn "DNS for $DOMAIN resolves to $resolved, this host is $PUBLIC_IP — certbot may fail"
    fi
  fi
}

# Strip CR, a leading BOM, bracketed-paste markers, and surrounding whitespace.
_ask_normalize_paste_line() {
  line="${line%$'\r'}"
  line="${line#$'\xef\xbb\xbf'}"
  line="${line//$'\e[200~'/}"
  line="${line//$'\e[201~'/}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
}

# Read one paste line into `line`. Optional $1 is a timeout in seconds.
# No timeout waits until the next line or EOF.
_ask_read_paste_line() {
  line=""
  if [[ -n "${1-}" ]]; then
    if ! IFS= read -r -t "$1" line; then
      line=""
      return 1
    fi
  elif ! IFS= read -r line; then
    line=""
    return 1
  fi
  _ask_normalize_paste_line
  return 0
}

# Drop lines already sitting in the buffer so the outer shell does not run them.
_ask_drain_paste() {
  local junk=""
  while IFS= read -r -t 0.2 junk; do
    :
  done
  return 0
}

# If a certificate follows the Config line, take it. Otherwise leave CERT_MODE alone.
_ask_take_pasted_certs() {
  local line="" chain="" key="" saw_key=0 key_done=0

  while _ask_read_paste_line 3; do
    if [[ -n "$line" ]]; then
      break
    fi
  done

  if [[ -z "$line" ]]; then
    return 0
  fi
  if [[ "$line" != *"-----BEGIN CERTIFICATE-----"* ]]; then
    _ask_drain_paste
    die "Unexpected text after Config"
  fi

  chain="$line"$'\n'
  while _ask_read_paste_line; do
    if [[ "$line" == *"-----BEGIN PRIVATE KEY-----"* || "$line" == *"-----BEGIN RSA PRIVATE KEY-----"* || "$line" == *"-----BEGIN EC PRIVATE KEY-----"* ]]; then
      saw_key=1
      break
    fi
    if [[ -z "$line" ]]; then
      continue
    fi
    chain+="$line"$'\n'
  done
  if [[ "$saw_key" -ne 1 ]]; then
    _ask_drain_paste
    die "Private key is missing"
  fi

  key="$line"$'\n'
  while _ask_read_paste_line; do
    if [[ -z "$line" ]]; then
      continue
    fi
    key+="$line"$'\n'
    if [[ "$line" == *"-----END PRIVATE KEY-----"* || "$line" == *"-----END RSA PRIVATE KEY-----"* || "$line" == *"-----END EC PRIVATE KEY-----"* ]]; then
      key_done=1
      break
    fi
  done
  if [[ "$key_done" -ne 1 ]]; then
    _ask_drain_paste
    die "Private key is missing"
  fi

  FULLCHAIN_PEM="$chain"
  PRIVKEY_PEM="$key"
  CERT_MODE="paste"
}

# Default: one line — domain [country] [path] [uuid] [subId] [password]
ask_config_oneline() {
  log "Configuration (one line)"
  echo "Format: domain [country] [path] [uuid] [subId] [password]"
  echo "  Empty line → MINIMAL (panel only). Domain only → FULL, rest generated."
  echo "  After that line, paste fullchain.pem and privkey.pem to reuse them."
  echo "  Omit both to issue a new certificate."
  echo "  Migration example: kb1.example.com Germany mypath uuid-here subidhere MyPass"
  echo "Runtime will be created at ${DEPLOY_DIR} after dependencies succeed."
  echo

  _ask_init_vars

  local line=""
  read -r -p "Config: " line || true
  _ask_take_pasted_certs
  # shellcheck disable=SC2086
  set -- $line

  DOMAIN="${1-}"
  COUNTRY="${2-}"
  SUB_PATH="${3-}"
  CLIENT_UUID="${4-}"
  SUB_ID="${5-}"
  ADMIN_PASS="${6-}"

  SUB_PATH="${SUB_PATH#/}"
  SUB_PATH="${SUB_PATH%/}"

  _ask_normalize_domain
  _ask_validate_uuid_if_set
  _ask_apply_domain_mode
  _ask_ensure_admin_password
  _ask_summary_and_proceed
}

# Step-by-step wizard (hidden). Enable: USE_STEP_WIZARD=1 sudo bash install.sh
ask_config_wizard() {
  log "Configuration wizard (step-by-step)"
  echo "Domain given → FULL: VLESS XHTTP + Reality on :443 + site + HTTPS subscription."
  echo "  Optional: country, sub path, UUID, subId (for migration). Everything else is generated."
  echo "No domain → MINIMAL: clean 3x-ui panel only."
  echo "Runtime will be created at ${DEPLOY_DIR} after dependencies succeed."
  echo

  _ask_init_vars

  prompt "Domain name (optional)" ""
  DOMAIN="${REPLY}"
  _ask_normalize_domain

  prompt "Country / client email label (optional, default: client)" ""
  COUNTRY="${REPLY}"

  prompt "Subscription path name (optional, auto if empty)" ""
  SUB_PATH="${REPLY}"
  SUB_PATH="${SUB_PATH#/}"
  SUB_PATH="${SUB_PATH%/}"

  prompt "Client UUID (optional, auto if empty)" ""
  CLIENT_UUID="${REPLY}"
  _ask_validate_uuid_if_set

  prompt "Subscription ID / subId (optional, auto if empty)" ""
  SUB_ID="${REPLY}"

  _ask_apply_domain_mode

  local gen_pass
  gen_pass="$(rand_password)"
  prompt_secret "Panel admin password" "$gen_pass"
  ADMIN_PASS="${REPLY}"

  _ask_summary_and_proceed
}

ask_config() {
  if [[ "${USE_STEP_WIZARD:-0}" == "1" ]]; then
    ask_config_wizard
  else
    ask_config_oneline
  fi
}

#!/usr/bin/env bash
# 3x-ui panel API: login, change admin, enable subscription

PANEL_URL="${PANEL_URL:-http://127.0.0.1:2053}"
PANEL_COOKIE_JAR=""
PANEL_OLD_USER="admin"
PANEL_OLD_PASS="admin"

panel_init_cookie() {
  [[ -n "${PANEL_COOKIE_JAR}" && -f "${PANEL_COOKIE_JAR}" ]] && rm -f "${PANEL_COOKIE_JAR}"
  PANEL_COOKIE_JAR="$(mktemp)"
}

panel_cleanup_cookie() {
  [[ -n "${PANEL_COOKIE_JAR}" && -f "${PANEL_COOKIE_JAR}" ]] && rm -f "${PANEL_COOKIE_JAR}"
}

panel_login_payload() {
  jq -n --arg u "$1" --arg p "$2" '{username:$u,password:$p}'
}

# 3x-ui 3.8+: unsafe methods need X-CSRF-Token from GET /csrf-token (same cookie jar).
# Echoes token on success; returns 1 on failure (does not die).
panel_fetch_csrf() {
  local body token
  [[ -n "${PANEL_COOKIE_JAR}" && -f "${PANEL_COOKIE_JAR}" ]] || return 1
  body="$(curl -sS -c "${PANEL_COOKIE_JAR}" -b "${PANEL_COOKIE_JAR}" \
    -H 'Accept: application/json' \
    "${PANEL_URL}/csrf-token" 2>/dev/null || true)"
  token="$(echo "$body" | jq -r '.obj // empty' 2>/dev/null || true)"
  [[ -n "$token" && "$token" != "null" ]] || return 1
  printf '%s' "$token"
}

# Returns 0 on success, 1 on failure (does not die)
panel_login_try() {
  local user="$1"
  local pass="$2"
  local payload code body token
  token="$(panel_fetch_csrf)" || return 1
  payload="$(panel_login_payload "$user" "$pass")"
  body="$(curl -sS -c "${PANEL_COOKIE_JAR}" -b "${PANEL_COOKIE_JAR}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H "X-CSRF-Token: ${token}" \
    -d "$payload" \
    -w '\n%{http_code}' \
    "${PANEL_URL}/login" 2>/dev/null || true)"
  code="$(echo "$body" | tail -n1)"
  body="$(echo "$body" | sed '$d')"
  [[ "$code" == "200" ]] || return 1
  echo "$body" | jq -e '.success == true' >/dev/null 2>&1
}

panel_login() {
  local user="$1"
  local pass="$2"
  log "Logging into 3x-ui as ${user}"
  if ! panel_login_try "$user" "$pass"; then
    die "Panel login failed for user '${user}'"
  fi
}

# Force username/password via panel CLI (no need to know previous password).
# Container name matches docker-compose templates: mushrooms_3xui
panel_force_credentials() {
  log "Forcing panel credentials via CLI (user=${ADMIN_USER})"
  local out=""
  local ok=0

  if out="$(docker exec mushrooms_3xui /app/x-ui setting -username "${ADMIN_USER}" -password "${ADMIN_PASS}" 2>&1)"; then
    ok=1
  elif out="$(docker exec mushrooms_3xui x-ui setting -username "${ADMIN_USER}" -password "${ADMIN_PASS}" 2>&1)"; then
    ok=1
  fi

  if [[ "$ok" -ne 1 ]]; then
    warn "CLI credential reset failed: ${out:-empty}"
    warn "Falling back to login-based bootstrap"
    panel_bootstrap_auth
    panel_change_credentials
    return 0
  fi

  log "CLI setting output: ${out}"
  cd "${DEPLOY_DIR}"
  docker compose restart 3xui
  sleep 3
  wait_for_panel

  panel_init_cookie
  if ! panel_login_try "$ADMIN_USER" "$ADMIN_PASS"; then
    warn "Login after CLI reset still failed — falling back to interactive bootstrap"
    panel_bootstrap_auth
    panel_change_credentials
    return 0
  fi

  PANEL_OLD_USER="$ADMIN_USER"
  PANEL_OLD_PASS="$ADMIN_PASS"
  log "Logged in with wizard credentials after CLI reset"
}

# Fresh panel: admin/admin. Re-run: try wizard creds, else prompt for current.
panel_bootstrap_auth() {
  log "Authenticating to panel"
  if panel_login_try "admin" "admin"; then
    PANEL_OLD_USER="admin"
    PANEL_OLD_PASS="admin"
    log "Logged in with default admin/admin"
    return 0
  fi
  if panel_login_try "$ADMIN_USER" "$ADMIN_PASS"; then
    PANEL_OLD_USER="$ADMIN_USER"
    PANEL_OLD_PASS="$ADMIN_PASS"
    log "Logged in with wizard credentials (already configured)"
    return 0
  fi

  warn "Default admin/admin and wizard credentials failed"
  echo "Enter the current panel username/password to continue."
  prompt "Current panel username" "admin"
  PANEL_OLD_USER="${REPLY}"
  prompt_secret "Current panel password" ""
  PANEL_OLD_PASS="${REPLY}"
  [[ -n "$PANEL_OLD_PASS" ]] || die "Current panel password is required"
  panel_login "$PANEL_OLD_USER" "$PANEL_OLD_PASS"
}

panel_api_post() {
  # panel_api_post /panel/api/... json_body
  local path="$1"
  local json="$2"
  local token
  token="$(panel_fetch_csrf)" || {
    echo ''
    return 1
  }
  curl -sS -c "${PANEL_COOKIE_JAR}" -b "${PANEL_COOKIE_JAR}" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -H "X-CSRF-Token: ${token}" \
    -d "$json" \
    "${PANEL_URL}${path}"
}

panel_api_post_form() {
  local path="$1"
  shift
  local token
  token="$(panel_fetch_csrf)" || {
    echo ''
    return 1
  }
  curl -sS -c "${PANEL_COOKIE_JAR}" -b "${PANEL_COOKIE_JAR}" \
    -H 'Accept: application/json' \
    -H "X-CSRF-Token: ${token}" \
    "$@" \
    "${PANEL_URL}${path}"
}

panel_change_credentials() {
  if [[ "$PANEL_OLD_USER" == "$ADMIN_USER" && "$PANEL_OLD_PASS" == "$ADMIN_PASS" ]]; then
    log "Panel credentials already match wizard values — skip updateUser"
    return 0
  fi

  log "Changing panel admin credentials"
  local payload
  payload="$(jq -n \
    --arg ou "$PANEL_OLD_USER" \
    --arg op "$PANEL_OLD_PASS" \
    --arg nu "$ADMIN_USER" \
    --arg np "$ADMIN_PASS" \
    '{oldUsername:$ou,oldPassword:$op,newUsername:$nu,newPassword:$np}')"

  local resp
  resp="$(panel_api_post /panel/api/setting/updateUser "$payload" 2>/dev/null || true)"
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    resp="$(panel_api_post /panel/setting/updateUser "$payload" 2>/dev/null || true)"
  fi
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    warn "updateUser via JSON failed, trying form-urlencoded"
    resp="$(panel_api_post_form /panel/api/setting/updateUser \
      --data-urlencode "oldUsername=${PANEL_OLD_USER}" \
      --data-urlencode "oldPassword=${PANEL_OLD_PASS}" \
      --data-urlencode "newUsername=${ADMIN_USER}" \
      --data-urlencode "newPassword=${ADMIN_PASS}" 2>/dev/null || true)"
  fi
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    resp="$(panel_api_post_form /panel/setting/updateUser \
      --data-urlencode "oldUsername=${PANEL_OLD_USER}" \
      --data-urlencode "oldPassword=${PANEL_OLD_PASS}" \
      --data-urlencode "newUsername=${ADMIN_USER}" \
      --data-urlencode "newPassword=${ADMIN_PASS}" 2>/dev/null || true)"
  fi
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    die "Failed to change panel credentials: ${resp:-empty}"
  fi

  PANEL_OLD_USER="$ADMIN_USER"
  PANEL_OLD_PASS="$ADMIN_PASS"
  panel_login "$ADMIN_USER" "$ADMIN_PASS"
}

panel_get_all_settings() {
  local resp
  resp="$(panel_api_post /panel/api/setting/all '{}' 2>/dev/null || true)"
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    resp="$(panel_api_post /panel/setting/all '{}' 2>/dev/null || true)"
  fi
  echo "$resp"
}

panel_configure_subscription() {
  log "Enabling HTTPS subscription at https://${DOMAIN}:2096/${SUB_PATH}/"
  local all_resp settings
  all_resp="$(panel_get_all_settings)"
  echo "$all_resp" | jq -e '.success == true' >/dev/null 2>&1 \
    || die "Failed to read panel settings: $all_resp"

  settings="$(echo "$all_resp" | jq -c \
    --arg path "/${SUB_PATH}/" \
    --arg uri "https://${DOMAIN}:2096/${SUB_PATH}/" \
    --arg domain "${DOMAIN}" \
    --arg cert "/etc/3x-ui/certs/fullchain.pem" \
    --arg key "/etc/3x-ui/certs/privkey.pem" '
    .obj
    | .subEnable = true
    | .subListen = "0.0.0.0"
    | .subPort = 2096
    | .subPath = $path
    | .subURI = $uri
    | .subDomain = $domain
    | .subCertFile = $cert
    | .subKeyFile = $key
    | .subUpdates = 12
  ')"

  local resp
  resp="$(panel_api_post /panel/api/setting/update "$settings" 2>/dev/null || true)"
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    resp="$(panel_api_post /panel/setting/update "$settings" 2>/dev/null || true)"
  fi
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    die "Failed to update subscription settings: ${resp:-empty}"
  fi

  ufw allow 2096/tcp >/dev/null 2>&1 || true

  local r
  r="$(panel_api_post /panel/api/setting/restartPanel '{"delay":1}' 2>/dev/null || true)"
  if ! echo "$r" | jq -e '.success == true' >/dev/null 2>&1; then
    panel_api_post /panel/setting/restartPanel '{"delay":1}' >/dev/null 2>&1 || true
  fi
  sleep 3
  wait_for_panel
  panel_login "$ADMIN_USER" "$ADMIN_PASS"
}

SUBSCRIPTION_URL=""
compute_subscription_url() {
  SUBSCRIPTION_URL="https://${DOMAIN}:2096/${SUB_PATH}/${SUB_ID}"
}

# Smoke-test HTTPS subscription endpoint (TLS + HTTP response)
verify_subscription_https() {
  compute_subscription_url
  log "Verifying subscription URL: ${SUBSCRIPTION_URL}"
  local code i
  for i in $(seq 1 15); do
    code="$(curl -fsS -o /dev/null -w '%{http_code}' --connect-timeout 5 \
      "${SUBSCRIPTION_URL}" 2>/dev/null || true)"
    if [[ "$code" =~ ^(200|204)$ ]]; then
      log "Subscription HTTPS OK (HTTP ${code})"
      return 0
    fi
    # Some panels return 400 without matching client yet, but TLS worked if we got a code
    if [[ "$code" =~ ^[45][0-9][0-9]$ ]]; then
      warn "Subscription reachable over HTTPS but HTTP ${code} — check path/subId after inbounds exist"
      return 0
    fi
    sleep 2
  done
  die "Subscription HTTPS check failed for ${SUBSCRIPTION_URL} (last HTTP code: ${code:-none}). Check certs, UFW 2096, and DNS."
}

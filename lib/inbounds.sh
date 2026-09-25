#!/usr/bin/env bash
# Inbounds via 3x-ui API:
#   main    — VLESS + XHTTP + Reality on :443, target = nginx site on 127.0.0.1:8443
#   reserve — VLESS TLS TCP / WS, created DISABLED and without clients (ports stay closed in UFW)

REALITY_PORT=443
REALITY_TARGET="127.0.0.1:8443"
RESERVE_STATUS=""

# Write stdin to a file readable only by root (inbound JSON may contain the Reality private key)
_write_private() {
  local out="$1"
  (umask 077 && cat >"$out")
  chmod 600 "$out"
}

render_inbound_xhttp_reality() {
  mkdir -p "${DEPLOY_DIR}/generated"
  jq \
    --arg remark "${COUNTRY} XHTTP" \
    --arg uuid "$CLIENT_UUID" \
    --arg email "$COUNTRY" \
    --arg subid "$SUB_ID" \
    --arg comment "$COMMENT" \
    --arg path "$XHTTP_PATH" \
    --arg domain "$DOMAIN" \
    --arg target "$REALITY_TARGET" \
    --arg priv "$REALITY_PRIVATE_KEY" \
    --arg pub "$REALITY_PUBLIC_KEY" \
    --argjson port "$REALITY_PORT" \
    --argjson sids "$REALITY_SHORT_IDS_JSON" '
    .remark = $remark
    | .port = $port
    | .settings.clients[0] |= (.id = $uuid | .email = $email | .subId = $subid | .comment = $comment | .flow = "")
    | .streamSettings.xhttpSettings.path = $path
    | .streamSettings.realitySettings |= (
        .target = $target
        | .serverNames = [$domain]
        | .privateKey = $priv
        | .shortIds = $sids
        | .settings.publicKey = $pub
      )
    | .settings |= tojson
    | .streamSettings |= tojson
    | .sniffing |= tojson
    | .allocate |= tojson
  ' "${REPO_DIR}/templates/inbound-xhttp-reality.json" \
    | _write_private "${DEPLOY_DIR}/generated/inbound-xhttp-reality.json"
}

render_inbound_reserve() {
  mkdir -p "${DEPLOY_DIR}/generated"
  local country_esc domain_esc tcp_tpl ws_tpl
  country_esc="$(json_escape "$COUNTRY")"
  domain_esc="$(json_escape "$DOMAIN")"

  tcp_tpl="$(cat "${REPO_DIR}/templates/inbound-tcp.json.tpl")"
  ws_tpl="$(cat "${REPO_DIR}/templates/inbound-ws.json.tpl")"

  tcp_tpl="${tcp_tpl//__DOMAIN__/$domain_esc}"
  tcp_tpl="${tcp_tpl//__COUNTRY__/$country_esc}"
  tcp_tpl="${tcp_tpl//__TCP_PORT__/$TCP_PORT}"

  ws_tpl="${ws_tpl//__DOMAIN__/$domain_esc}"
  ws_tpl="${ws_tpl//__COUNTRY__/$country_esc}"
  ws_tpl="${ws_tpl//__WS_PORT__/$WS_PORT}"

  echo "$tcp_tpl" | jq . | _write_private "${DEPLOY_DIR}/generated/inbound-tcp.json"
  echo "$ws_tpl" | jq . | _write_private "${DEPLOY_DIR}/generated/inbound-ws.json"
}

# POST inbound; echo response to stdout; return 0 if success
_post_inbound_payload() {
  local payload="$1"
  local resp
  resp="$(panel_api_post /panel/api/inbounds/add "$payload" 2>/dev/null || true)"
  if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    resp="$(panel_api_post /panel/inbounds/add "$payload" 2>/dev/null || true)"
  fi
  printf '%s' "$resp"
  echo "$resp" | jq -e '.success == true' >/dev/null 2>&1
}

_post_inbound_form() {
  local file="$1"
  local up down total remark enable expiryTime listen port protocol settings streamSettings sniffing resp
  up="$(jq -r '.up' "$file")"
  down="$(jq -r '.down' "$file")"
  total="$(jq -r '.total' "$file")"
  remark="$(jq -r '.remark' "$file")"
  enable="$(jq -r '.enable' "$file")"
  expiryTime="$(jq -r '.expiryTime' "$file")"
  listen="$(jq -r '.listen' "$file")"
  port="$(jq -r '.port' "$file")"
  protocol="$(jq -r '.protocol' "$file")"
  settings="$(jq -r '.settings' "$file")"
  streamSettings="$(jq -r '.streamSettings' "$file")"
  sniffing="$(jq -r '.sniffing' "$file")"

  # Via panel_api_post_form so CSRF (3x-ui 3.8+) is attached automatically
  resp="$(panel_api_post_form /panel/api/inbounds/add \
    --data-urlencode "up=${up}" \
    --data-urlencode "down=${down}" \
    --data-urlencode "total=${total}" \
    --data-urlencode "remark=${remark}" \
    --data-urlencode "enable=${enable}" \
    --data-urlencode "expiryTime=${expiryTime}" \
    --data-urlencode "listen=${listen}" \
    --data-urlencode "port=${port}" \
    --data-urlencode "protocol=${protocol}" \
    --data-urlencode "settings=${settings}" \
    --data-urlencode "streamSettings=${streamSettings}" \
    --data-urlencode "sniffing=${sniffing}" 2>/dev/null || true)"
  printf '%s' "$resp"
  echo "$resp" | jq -e '.success == true' >/dev/null 2>&1
}

# add_inbound file label — returns 0 on success, 1 on failure (caller decides)
ADD_INBOUND_LAST_RESP=""
add_inbound() {
  local file="$1"
  local label="$2"
  log "Creating inbound: ${label}"
  local payload resp
  payload="$(cat "$file")"

  if resp="$(_post_inbound_payload "$payload")" && echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "$resp" | jq -c '{success,msg}' || true
    return 0
  fi

  warn "JSON body add failed for ${label}, trying form-urlencoded"
  if resp="$(_post_inbound_form "$file")" && echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
    echo "$resp" | jq -c '{success,msg}' || true
    return 0
  fi

  ADD_INBOUND_LAST_RESP="${resp:-empty}"
  return 1
}

create_inbounds() {
  render_inbound_xhttp_reality
  render_inbound_reserve

  ensure_port_free "$REALITY_PORT"
  add_inbound \
    "${DEPLOY_DIR}/generated/inbound-xhttp-reality.json" \
    "VLESS XHTTP Reality :${REALITY_PORT} (main)" \
    || die "Failed to add main inbound: ${ADD_INBOUND_LAST_RESP}"

  # Reserve inbounds: failure is not fatal — main channel already exists
  local tcp_ok="created" ws_ok="created"
  add_inbound "${DEPLOY_DIR}/generated/inbound-tcp.json" "VLESS TCP TLS :${TCP_PORT} (reserve, disabled)" \
    || { warn "Reserve TCP inbound not created: ${ADD_INBOUND_LAST_RESP}"; tcp_ok="NOT created"; }
  add_inbound "${DEPLOY_DIR}/generated/inbound-ws.json" "VLESS WS TLS :${WS_PORT} (reserve, disabled)" \
    || { warn "Reserve WS inbound not created: ${ADD_INBOUND_LAST_RESP}"; ws_ok="NOT created"; }
  RESERVE_STATUS="TCP ${tcp_ok}, WS ${ws_ok}"
}

# The site must answer through Reality on :443 (unauthenticated TLS is forwarded to nginx)
verify_selfsteal_site() {
  log "Verifying site through Reality: https://${DOMAIN}/ via 127.0.0.1:${REALITY_PORT}"
  local code i
  for i in $(seq 1 15); do
    code="$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --connect-timeout 5 \
      --resolve "${DOMAIN}:${REALITY_PORT}:127.0.0.1" \
      "https://${DOMAIN}/" 2>/dev/null || true)"
    if [[ "$code" == "200" ]]; then
      log "Selfsteal OK: site answers through Reality on :${REALITY_PORT}"
      return 0
    fi
    sleep 2
  done
  die "Site is not reachable through Reality on :${REALITY_PORT} (last HTTP code: ${code:-none}). Check:
  ss -tlnp | grep -E ':(443|8443)\\b'
  curl -vk --resolve ${DOMAIN}:8443:127.0.0.1 https://${DOMAIN}:8443/
  docker logs --tail 50 mushrooms_3xui"
}

#!/usr/bin/env bash
# Create VLESS TCP+TLS and WS+TLS inbounds via 3x-ui API

render_inbound_templates() {
  mkdir -p "${DEPLOY_DIR}/generated"
  local comment_esc country_esc domain_esc
  comment_esc="$(json_escape "$COMMENT")"
  country_esc="$(json_escape "$COUNTRY")"
  domain_esc="$(json_escape "$DOMAIN")"

  local tcp_tpl ws_tpl
  tcp_tpl="$(cat "${REPO_DIR}/templates/inbound-tcp.json.tpl")"
  ws_tpl="$(cat "${REPO_DIR}/templates/inbound-ws.json.tpl")"

  tcp_tpl="${tcp_tpl//__DOMAIN__/$domain_esc}"
  tcp_tpl="${tcp_tpl//__COUNTRY__/$country_esc}"
  tcp_tpl="${tcp_tpl//__CLIENT_UUID__/$CLIENT_UUID}"
  tcp_tpl="${tcp_tpl//__SUB_ID__/$SUB_ID}"
  tcp_tpl="${tcp_tpl//__TCP_PORT__/$TCP_PORT}"
  tcp_tpl="${tcp_tpl//__COMMENT__/$comment_esc}"

  ws_tpl="${ws_tpl//__DOMAIN__/$domain_esc}"
  ws_tpl="${ws_tpl//__COUNTRY__/$country_esc}"
  ws_tpl="${ws_tpl//__CLIENT_UUID__/$CLIENT_UUID}"
  ws_tpl="${ws_tpl//__SUB_ID__/$SUB_ID}"
  ws_tpl="${ws_tpl//__WS_PORT__/$WS_PORT}"
  ws_tpl="${ws_tpl//__COMMENT__/$comment_esc}"

  echo "$tcp_tpl" | jq . >"${DEPLOY_DIR}/generated/inbound-tcp.json"
  echo "$ws_tpl" | jq . >"${DEPLOY_DIR}/generated/inbound-ws.json"

  # Compat payload without finalmask/testseed (older 3x-ui / xray builds)
  jq '
    .settings |= (fromjson | del(.testseed) | tojson)
    | .streamSettings |= (fromjson | del(.finalmask) | tojson)
  ' "${DEPLOY_DIR}/generated/inbound-tcp.json" \
    >"${DEPLOY_DIR}/generated/inbound-tcp-compat.json"
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

add_inbound() {
  local file="$1"
  local label="$2"
  local compat="${3-}"
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

  if [[ -n "$compat" && -f "$compat" ]]; then
    warn "Retrying ${label} without finalmask/testseed (compat)"
    if add_inbound "$compat" "${label} (compat)"; then
      return 0
    fi
  fi

  die "Failed to add inbound ${label}: ${resp:-empty}"
}

create_inbounds() {
  render_inbound_templates
  add_inbound \
    "${DEPLOY_DIR}/generated/inbound-tcp.json" \
    "VLESS TCP TLS :${TCP_PORT}" \
    "${DEPLOY_DIR}/generated/inbound-tcp-compat.json"
  add_inbound \
    "${DEPLOY_DIR}/generated/inbound-ws.json" \
    "VLESS WS TLS :${WS_PORT}"
}

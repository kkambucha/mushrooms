#!/usr/bin/env bash
# Shared helpers for mushrooms installer

set -euo pipefail

log()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

rand_hex() {
  local n="${1:-16}"
  openssl rand -hex "$(( (n + 1) / 2 ))" | head -c "$n"
}

rand_alnum() {
  local n="${1:-16}"
  tr -dc 'a-z0-9' </dev/urandom | head -c "$n"
}

rand_port() {
  # 20000-50000
  echo $((20000 + RANDOM % 30001))
}

rand_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20
}

prompt() {
  # prompt "Label" "default" -> sets REPLY
  local label="$1"
  local def="${2-}"
  if [[ -n "$def" ]]; then
    read -r -p "$label [$def]: " REPLY || true
    REPLY="${REPLY:-$def}"
  else
    read -r -p "$label: " REPLY || true
  fi
}

prompt_secret() {
  local label="$1"
  local def="${2-}"
  if [[ -n "$def" ]]; then
    read -r -p "$label [generated]: " REPLY || true
    REPLY="${REPLY:-$def}"
  else
    read -r -p "$label: " REPLY || true
  fi
}

prompt_multiline_pem() {
  # Reads until a line containing only END marker or empty line after BEGIN
  local label="$1"
  local end_marker="$2"
  echo "$label"
  echo "(paste PEM, then a line with only 'END' when finished; leave empty first line to skip)"
  local line first=1 buf=""
  while IFS= read -r line; do
    if [[ "$first" -eq 1 && -z "$line" ]]; then
      REPLY=""
      return 0
    fi
    first=0
    if [[ "$line" == "END" ]]; then
      break
    fi
    buf+="$line"$'\n'
    if [[ "$line" == *"$end_marker"* ]]; then
      break
    fi
  done
  REPLY="$buf"
}

json_escape() {
  # Escape string for JSON embedding
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

render_template() {
  # render_template infile outfile — replaces __VAR__ from environment
  local infile="$1"
  local outfile="$2"
  local content
  content="$(cat "$infile")"
  # Replace known placeholders
  local vars=(
    DOMAIN ACME_EMAIL COUNTRY CLIENT_UUID SUB_ID SUB_PATH
    TCP_PORT WS_PORT COMMENT ADMIN_USER ADMIN_PASS
    HTTP_ROOT HTTPS_SERVER
  )
  local v val
  for v in "${vars[@]}"; do
    val="${!v-}"
    content="${content//__${v}__/$val}"
  done
  printf '%s' "$content" >"$outfile"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Run as root: sudo bash install.sh"
  fi
}

detect_public_ip() {
  local ip=""
  ip="$(curl -4 -fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  printf '%s' "$ip"
}

check_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    warn "Cannot detect OS; continuing anyway"
    return 0
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && "${ID:-}" != "debian" ]]; then
    warn "Expected Ubuntu/Debian, found ${ID:-unknown}"
  fi
  local ver="${VERSION_ID:-0}"
  local major="${ver%%.*}"
  if [[ "$ID" == "ubuntu" && "$major" -lt 20 ]]; then
    die "Ubuntu 20.04+ required (found $ver)"
  fi
}

port_in_use() {
  local port="$1"
  ss -tuln | grep -qE ":${port}\s" && return 0
  return 1
}

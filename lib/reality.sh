#!/usr/bin/env bash
# Reality helpers: X25519 keys, shortIds, XHTTP path.
# Keys are produced with openssl (no dependency on `xray x25519` output format,
# and the 3x-ui container is not running yet when the wizard asks for them).

# PKCS#8 DER prefix for a raw 32-byte X25519 private key (RFC 8410)
_REALITY_PKCS8_PREFIX='\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x6e\x04\x22\x04\x20'

# stdin (binary) -> base64url without padding
reality_b64url_encode() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# $1 base64url -> stdout (binary)
reality_b64url_decode() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '_-' '/+')"
  while (( ${#s} % 4 )); do s+='='; done
  printf '%s' "$s" | openssl base64 -d -A
}

# 0 if $1 looks like a Reality/X25519 private key (base64url, 32 bytes)
reality_validate_private() {
  local key="$1" n
  [[ "$key" =~ ^[A-Za-z0-9_-]{43}$ ]] || return 1
  n="$(reality_b64url_decode "$key" | wc -c | tr -d ' ')"
  [[ "$n" == "32" ]]
}

# Sets REALITY_PRIVATE_KEY and REALITY_PUBLIC_KEY
reality_generate_keypair() {
  local tmp
  tmp="$(mktemp)"
  if ! openssl genpkey -algorithm X25519 -out "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    die "openssl cannot generate X25519 keys (OpenSSL 1.1.1+ required)"
  fi
  REALITY_PRIVATE_KEY="$(openssl pkey -in "$tmp" -outform DER 2>/dev/null | tail -c 32 | reality_b64url_encode)"
  REALITY_PUBLIC_KEY="$(openssl pkey -in "$tmp" -pubout -outform DER 2>/dev/null | tail -c 32 | reality_b64url_encode)"
  rm -f "$tmp"
  reality_validate_private "$REALITY_PRIVATE_KEY" || die "Generated Reality private key is invalid"
  [[ ${#REALITY_PUBLIC_KEY} -eq 43 ]] || die "Generated Reality public key is invalid"
}

# $1 private key (base64url) -> sets REALITY_PUBLIC_KEY
reality_derive_public() {
  local priv="$1" tmp
  reality_validate_private "$priv" || die "Reality private key must be 43 base64url chars (32 bytes)"
  tmp="$(mktemp)"
  {
    printf '%b' "${_REALITY_PKCS8_PREFIX}"
    reality_b64url_decode "$priv"
  } >"$tmp"
  REALITY_PUBLIC_KEY="$(openssl pkey -inform DER -in "$tmp" -pubout -outform DER 2>/dev/null | tail -c 32 | reality_b64url_encode)"
  rm -f "$tmp"
  [[ ${#REALITY_PUBLIC_KEY} -eq 43 ]] || die "Cannot derive Reality public key from the private key"
}

# Sets REALITY_SHORT_IDS_JSON (JSON array) and REALITY_SHORT_ID (first, used in links)
reality_generate_short_ids() {
  local ids=() len
  for len in 16 12 8 4; do
    ids+=("$(rand_hex "$len")")
  done
  REALITY_SHORT_IDS_JSON="$(printf '%s\n' "${ids[@]}" | jq -R . | jq -cs .)"
  REALITY_SHORT_ID="${ids[0]}"
}

# $1 comma-separated shortIds -> sets REALITY_SHORT_IDS_JSON, REALITY_SHORT_ID
reality_parse_short_ids() {
  local csv="$1" id ids=()
  local IFS=','
  for id in $csv; do
    id="${id//[[:space:]]/}"
    [[ -n "$id" ]] || continue
    id="${id,,}"
    [[ "$id" =~ ^[0-9a-f]{2,16}$ ]] || die "Invalid shortId '${id}': hex, 2-16 chars"
    (( ${#id} % 2 == 0 )) || die "Invalid shortId '${id}': length must be even"
    ids+=("$id")
  done
  (( ${#ids[@]} > 0 )) || die "No valid shortIds given"
  (( ${#ids[@]} <= 8 )) || die "Too many shortIds (max 8)"
  REALITY_SHORT_IDS_JSON="$(printf '%s\n' "${ids[@]}" | jq -R . | jq -cs .)"
  REALITY_SHORT_ID="${ids[0]}"
}

# 0 if $1 is an acceptable XHTTP path
reality_validate_path() {
  [[ "$1" =~ ^/[A-Za-z0-9._~/-]*$ ]]
}

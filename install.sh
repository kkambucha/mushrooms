#!/usr/bin/env bash
# Mushrooms — interactive installer for nginx + 3x-ui (VLESS TLS TCP + WS)
# Target: Ubuntu 20.04+ (Debian-compatible)
# Usage: sudo bash install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/mushrooms}"

# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=lib/ask.sh
source "${REPO_DIR}/lib/ask.sh"
# shellcheck source=lib/deps.sh
source "${REPO_DIR}/lib/deps.sh"
# shellcheck source=lib/certs.sh
source "${REPO_DIR}/lib/certs.sh"
# shellcheck source=lib/compose.sh
source "${REPO_DIR}/lib/compose.sh"
# shellcheck source=lib/panel.sh
source "${REPO_DIR}/lib/panel.sh"
# shellcheck source=lib/inbounds.sh
source "${REPO_DIR}/lib/inbounds.sh"
# shellcheck source=lib/summary.sh
source "${REPO_DIR}/lib/summary.sh"

main() {
  require_root
  check_ubuntu

  echo
  echo "╔══════════════════════════════════════════════╗"
  echo "║  Mushrooms installer — 3x-ui VLESS TLS       ║"
  echo "╚══════════════════════════════════════════════╝"
  echo

  ask_config
  install_deps
  stop_conflicting_web
  configure_ufw

  if [[ -d "${DEPLOY_DIR}/data/db" ]] && [[ -n "$(ls -A "${DEPLOY_DIR}/data/db" 2>/dev/null || true)" ]]; then
    warn "Existing panel database found at ${DEPLOY_DIR}/data/db"
    prompt "Continue anyway? (may fail if admin password already changed)" "no"
    [[ "${REPLY,,}" == "yes" || "${REPLY,,}" == "y" ]] || die "Aborted — remove ${DEPLOY_DIR} for a clean install"
  fi

  prepare_deploy_dir

  # Certificates + nginx bootstrap
  if [[ "$CERT_MODE" == "paste" ]]; then
    write_pasted_certs
    build_nginx_https
    compose_up
  else
    # HTTP-only nginx first for ACME challenge
    write_self_signed_placeholder
    build_nginx_http_only
    compose_up
    sleep 2
    issue_letsencrypt
    build_nginx_https
    compose_restart_nginx
    install_cert_renew_hook
  fi

  # Ensure 3x-ui is up (compose_up already started it; restart after certs ready)
  cd "${DEPLOY_DIR}"
  docker compose up -d
  wait_for_panel

  panel_init_cookie
  trap panel_cleanup_cookie EXIT

  panel_bootstrap_auth
  panel_change_credentials
  panel_configure_subscription
  create_inbounds
  verify_subscription_https

  write_summary

  log "Done."
}

main "$@"

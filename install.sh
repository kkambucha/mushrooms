#!/usr/bin/env bash
# Mushrooms — interactive installer for nginx + 3x-ui (VLESS TLS TCP + WS)
# Target: Ubuntu 20.04+ (Debian-compatible)
# Usage: sudo bash install.sh
#
# Leave wizard fields empty → MINIMAL: clean 3x-ui panel only.
# Fill domain+country+path+UUID+subId → FULL: site + inbounds + HTTPS subscription.

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
  echo "║  Mushrooms installer — 3x-ui                 ║"
  echo "╚══════════════════════════════════════════════╝"
  echo
  echo "Source (this script): ${REPO_DIR}"
  echo "Runtime (after success): ${DEPLOY_DIR}"
  echo "  → /opt/mushrooms is created only after dependencies succeed."
  echo

  ask_config
  install_deps
  stop_conflicting_web
  configure_ufw

  if [[ -d "${DEPLOY_DIR}/data/db" ]] && [[ -n "$(ls -A "${DEPLOY_DIR}/data/db" 2>/dev/null || true)" ]]; then
    warn "Existing panel database found at ${DEPLOY_DIR}/data/db"
    warn "Admin password will be reset to wizard values via CLI (no need to know the old password)."
    prompt "Continue anyway?" "yes"
    [[ "${REPLY,,}" == "yes" || "${REPLY,,}" == "y" ]] || die "Aborted — remove ${DEPLOY_DIR}/data/db for a clean DB"
  fi

  prepare_deploy_dir

  if [[ "${ENABLE_SITE}" == "true" ]]; then
    if [[ "$CERT_MODE" == "paste" ]]; then
      write_pasted_certs
      build_nginx_https
      compose_up
    else
      write_self_signed_placeholder
      build_nginx_http_only
      compose_up
      sleep 2
      issue_letsencrypt
      build_nginx_https
      compose_restart_nginx
      install_cert_renew_hook
    fi
  else
    remove_cert_renew_hook
    compose_up
  fi

  cd "${DEPLOY_DIR}"
  docker compose up -d --remove-orphans
  wait_for_panel

  panel_init_cookie
  trap panel_cleanup_cookie EXIT

  # Always force wizard credentials via CLI — do not guess admin/admin
  panel_force_credentials

  if [[ "${INSTALL_MODE}" == "full" ]]; then
    panel_configure_subscription
    create_inbounds
    verify_subscription_https
  else
    log "MINIMAL mode — skipping inbound/subscription API setup (configure in the panel UI)"
  fi

  write_summary

  log "Done. Deploy directory: ${DEPLOY_DIR}"
  log "Next: cd ${DEPLOY_DIR} && docker compose ps"
}

main "$@"

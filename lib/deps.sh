#!/usr/bin/env bash
# Install system dependencies: Docker, jq, curl, certbot, ufw helpers

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    log "docker compose OK: $(docker compose version --short 2>/dev/null || docker compose version | head -n1)"
    return 0
  fi

  log "Installing / repairing Docker via get.docker.com (includes compose plugin)"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker || true

  if docker compose version >/dev/null 2>&1; then
    log "docker compose OK after get.docker.com"
    return 0
  fi

  die "docker compose is still missing. Install official Docker from https://get.docker.com (do NOT apt-install docker-compose-plugin without the Docker apt repo). See README."
}

install_deps() {
  log "Installing dependencies"
  echo "Note: runtime directory ${DEPLOY_DIR} is created only AFTER deps succeed."

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    jq openssl dnsutils \
    ufw \
    certbot

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker not found — installing via get.docker.com"
  else
    log "Docker binary present — ensuring compose plugin works"
  fi
  ensure_docker_compose

  command -v jq >/dev/null 2>&1 || die "jq is required"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  # certbot only required when issuing LE for a site
  if [[ "${ENABLE_SITE:-false}" == "true" && "${CERT_MODE:-}" == "certbot" ]]; then
    command -v certbot >/dev/null 2>&1 || die "certbot is required for Let's Encrypt"
  fi
}

configure_ufw() {
  log "Configuring UFW"
  ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow 2053/tcp >/dev/null 2>&1 || true

  if [[ "${ENABLE_SITE:-false}" == "true" ]]; then
    ufw allow 80/tcp >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
  fi

  if [[ "${INSTALL_MODE:-minimal}" == "full" ]]; then
    ufw allow 2096/tcp >/dev/null 2>&1 || true
    # Reserve TCP/WS inbounds are created disabled — their ports stay closed.
    # To use the reserve: enable inbound in panel (client is already attached), `ufw allow <port>/tcp`.
  fi

  if ufw status | grep -qi inactive; then
    echo "y" | ufw enable || true
  fi
  ufw reload || true
}

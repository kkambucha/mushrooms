#!/usr/bin/env bash
# Install system dependencies: Docker, jq, curl, certbot, ufw helpers

install_deps() {
  log "Installing dependencies"

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    jq openssl dnsutils \
    ufw \
    certbot

  if ! command -v docker >/dev/null 2>&1; then
    log "Installing Docker"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
  else
    log "Docker already installed"
  fi

  if ! docker compose version >/dev/null 2>&1; then
    apt-get install -y docker-compose-plugin || true
  fi

  docker compose version >/dev/null 2>&1 || die "docker compose plugin is required"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v certbot >/dev/null 2>&1 || die "certbot is required"
}

configure_ufw() {
  log "Configuring UFW"
  ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
  ufw allow 80/tcp >/dev/null 2>&1 || true
  ufw allow 443/tcp >/dev/null 2>&1 || true
  ufw allow 2053/tcp >/dev/null 2>&1 || true
  ufw allow "${TCP_PORT}/tcp" >/dev/null 2>&1 || true
  ufw allow "${WS_PORT}/tcp" >/dev/null 2>&1 || true
  # Enable non-interactively if inactive
  if ufw status | grep -qi inactive; then
    echo "y" | ufw enable || true
  fi
  ufw reload || true
}

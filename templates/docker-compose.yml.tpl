services:
  nginx:
    image: nginx:1.27-alpine
    container_name: mushrooms_nginx
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./site:/var/www/html:ro
      - ./certs:/etc/nginx/certs:ro
      - ./certbot/www:/var/www/certbot:ro

  3xui:
    # Pin a release tag in production if you need bit-for-bit reproducibility.
    # Compat fallback strips finalmask/testseed when this image rejects them.
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: mushrooms_3xui
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./data/db:/etc/x-ui/
      - ./certs:/etc/3x-ui/certs/:ro
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "false"
    tty: true

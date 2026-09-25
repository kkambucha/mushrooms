services:
  3xui:
    # Pinned: inbound JSON / API verified against 3x-ui v3.8.5 (Xray v26.9.9).
    image: ghcr.io/mhsanaei/3x-ui:v3.8.5
    container_name: mushrooms_3xui
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./data/db:/etc/x-ui/
      - ./certs:/etc/3x-ui/certs/:ro
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "false"
      XUI_INIT_WEB_BASE_PATH: "/"
    tty: true

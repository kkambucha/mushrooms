services:
  3xui:
    # Pin a release tag in production if you need bit-for-bit reproducibility.
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

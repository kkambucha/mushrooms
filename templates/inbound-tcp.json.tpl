{
  "up": 0,
  "down": 0,
  "total": 0,
  "remark": "__COUNTRY__ TCP",
  "enable": false,
  "expiryTime": 0,
  "listen": "",
  "port": __TCP_PORT__,
  "protocol": "vless",
  "settings": "{\"clients\":[],\"decryption\":\"none\",\"encryption\":\"none\"}",
  "streamSettings": "{\"network\":\"tcp\",\"tcpSettings\":{\"acceptProxyProtocol\":false},\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"__DOMAIN__\",\"minVersion\":\"1.2\",\"maxVersion\":\"1.3\",\"cipherSuites\":\"\",\"rejectUnknownSni\":false,\"disableSystemRoot\":false,\"enableSessionResumption\":false,\"certificates\":[{\"ocspStapling\":0,\"oneTimeLoading\":false,\"usage\":\"encipherment\",\"buildChain\":false,\"certificateFile\":\"/etc/3x-ui/certs/fullchain.pem\",\"keyFile\":\"/etc/3x-ui/certs/privkey.pem\",\"useFile\":true}],\"alpn\":[\"h2\",\"http/1.1\"],\"echServerKeys\":\"\",\"settings\":{\"fingerprint\":\"chrome\",\"echConfigList\":\"\",\"pinnedPeerCertSha256\":[],\"verifyPeerCertByName\":\"\"}}}",
  "sniffing": "{\"enabled\":false,\"destOverride\":[],\"metadataOnly\":false,\"routeOnly\":false}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}

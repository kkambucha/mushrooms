worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server_tokens off;

    # HTTP: ACME + redirect to HTTPS once certs exist
    server {
        listen 80;
        listen [::]:80;
        server_name __DOMAIN__;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            __HTTP_ROOT__
        }
    }

    # HTTPS site (enabled after certificates are present)
    __HTTPS_SERVER__
}

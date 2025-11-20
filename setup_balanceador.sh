#!/bin/bash

echo "Creando estructura de carpetas..."
mkdir -p nginx/conf.d
mkdir -p certs
mkdir -p logs

echo "Creando docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: "3.9"

services:
  nginx:
    image: nginx:1.27-alpine
    container_name: lb_contraloria
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./certs:/etc/nginx/certs:ro
      - ./logs:/var/log/nginx
    networks:
      - lb-net

networks:
  lb-net:
    driver: bridge
EOF

echo "Creando nginx/nginx.conf..."
cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;

events {
    worker_connections 4096;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Seguridad general
    server_tokens off;
    sendfile on;
    keepalive_timeout 65;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_rate:10m rate=10r/s;

    # Logs
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    # Upstreams (tus frontends)
    upstream frontends_cluster {
        zone upstream_balancer 64k;

        server 10.10.8.18:80 weight=1 max_fails=3 fail_timeout=10s;
        server 10.10.8.18:80 weight=1 max_fails=3 fail_timeout=10s;
        server 10.10.8.19:80 weight=1 max_fails=3 fail_timeout=10s;
        server 10.10.8.19:80 weight=1 max_fails=3 fail_timeout=10s;

        keepalive 32;
    }

    # Configuración global SSL
    ssl_protocols TLSv1.3 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;

    include /etc/nginx/conf.d/*.conf;
}
EOF

echo "Creando nginx/conf.d/dev.contraloria.gob.gt.conf..."
cat > nginx/conf.d/dev.contraloria.gob.gt.conf << 'EOF'
server {
    listen 80;
    server_name dev.contraloria.gob.gt;

    # Redirigir todo a https
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name dev.contraloria.gob.gt;

    # Certificados
    ssl_certificate /etc/nginx/certs/cert.pem;
    ssl_certificate_key /etc/nginx/certs/key.pem;

    # Seguridad
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # Rate limiting
    limit_req zone=api_rate burst=20 nodelay;

    # Proxy al cluster
    location / {
        proxy_pass http://frontends_cluster;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
        proxy_send_timeout 30s;
    }

    # Health check
    location /health {
        access_log off;
        return 200 "OK";
    }
}
EOF

echo "Listo. Todos los archivos fueron creados."
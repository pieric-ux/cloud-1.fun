upstream ingress {
    zone ingress 64k;
    server 10.1.10.10;
    keepalive 2;
}

server {
    listen 80;
    server_name ingress.cloud-1.fun ingress01.cloud-1.fun;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name ingress.cloud-1.fun ingress01.cloud-1.fun;

    ssl_certificate     /etc/letsencrypt/live/cloud-1.fun/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cloud-1.fun/privkey.pem;
    add_header Strict-Transport-Security "max-age=31536000;";

    client_max_body_size 10M;

    location / {
        proxy_pass http://ingress;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

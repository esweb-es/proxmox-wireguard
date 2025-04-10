echo "🔧 Configurando WG-Easy dentro del contenedor..."
pct exec $LXC_ID -- bash -c "
mkdir -p /root/wireguard
cat > /root/wireguard/docker-compose.yml <<'EOF'
volumes:
  etc_wireguard:

services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    environment:
      - LANG=es
      - WG_HOST=$WG_HOST
      - PASSWORD=$WEB_PASSWORD
      # Ejemplos comentados:
      - WG_PORT=51820
      - PORT=51821
      - WG_DEFAULT_DNS=1.1.1.1
      # - UI_TRAFFIC_STATS=true
      # - UI_ENABLE_SORT_CLIENTS=true
      # - WG_ENABLE_ONE_TIME_LINKS=true
      # - WG_ENABLE_EXPIRES_TIME=true
      # - UI_CHART_TYPE=2
    volumes:
      - etc_wireguard:/etc/wireguard
    ports:
      - '51820:51820/udp'
      - '51821:51821/tcp'
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF

cd /root/wireguard && docker compose up -d
"

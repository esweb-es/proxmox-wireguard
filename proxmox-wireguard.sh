# Configurar wg-easy con contraseña
echo "🔧 Configurando wg-easy..."
pct exec $CT_ID -- bash -c "
    mkdir -p /opt/wg-easy/data
    cat <<'EOF' > /opt/wg-easy/docker-compose.yml
services:
  wg-easy:
    environment:
      - WG_HOST=\$(hostname -I | awk '{print \$1}')
      - PASSWORD=__PASSWORD__
      - WG_PORT=__WG_PORT__
      - WG_ADMIN_PORT=__WG_ADMIN_PORT__
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
    image: weejewel/wg-easy
    container_name: wg-easy
    volumes:
      - /opt/wg-easy/data:/etc/wireguard
    ports:
      - '__WG_PORT__:__WG_PORT__/udp'
      - '__WG_ADMIN_PORT__:__WG_ADMIN_PORT__/tcp'
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF

    sed -i \"s/__PASSWORD__/$WG_ADMIN_PASSWORD/\" /opt/wg-easy/docker-compose.yml
    sed -i \"s/__WG_PORT__/$WG_PORT/\" /opt/wg-easy/docker-compose.yml
    sed -i \"s/__WG_ADMIN_PORT__/$WG_ADMIN_PORT/\" /opt/wg-easy/docker-compose.yml
    cd /opt/wg-easy && docker compose up -d
"

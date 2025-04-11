#!/bin/bash
set -euo pipefail

echo "🌐 Dominio o IP pública para WG_HOST (ej: vpn.midominio.com):"
read -rp "WG_HOST: " WG_HOST

read -rp "🚪 Puerto para WireGuard (por defecto 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}

read -rp "🖥️ Puerto para interfaz web (por defecto 51821): " WG_ADMIN_PORT
WG_ADMIN_PORT=${WG_ADMIN_PORT:-51821}

read -rsp "🔐 Contraseña para interfaz web: " PASSWORD
echo

echo "🔐 Generando hash seguro con htpasswd..."
HASH=$(htpasswd -nbBC 12 admin "$PASSWORD" | cut -d: -f2)

echo "📄 Generando archivo .env..."
cat > .env <<EOF
WG_HOST=$WG_HOST
PASSWORD_HASH=$HASH
WG_PORT=$WG_PORT
WG_ADMIN_PORT=$WG_ADMIN_PORT
WG_DEFAULT_ADDRESS=10.8.0.x
WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
LANG=es
EOF

echo "📄 Generando archivo docker-compose.yml..."
cat > docker-compose.yml <<'EOF'
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    env_file:
      - .env
    volumes:
      - ./data:/etc/wireguard
    ports:
      - ${WG_PORT}:${WG_PORT}/udp
      - ${WG_ADMIN_PORT}:${WG_ADMIN_PORT}/tcp
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF

echo "🚀 Iniciando WG-Easy con docker compose..."
docker compose up -d

echo -e "\n✅ ¡WG-Easy está corriendo!"
echo "🌐 Accedé a: http://$WG_HOST:$WG_ADMIN_PORT"
echo "👤 Usuario: admin"
echo "🔐 Contraseña: (la que ingresaste)"

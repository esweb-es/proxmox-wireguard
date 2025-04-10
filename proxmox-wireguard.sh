#!/bin/bash
set -euo pipefail

# Solicitar datos básicos
read -rp "➞️  IP/Dominio para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña web: " WEB_PASSWORD
echo
read -rsp "🔑 Contraseña root LXC: " ROOT_PASSWORD
echo

# Configuración
LXC_ID=$(pvesh get /cluster/nextid)
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"

# Verificar si la plantilla existe en local
if [[ ! -f "/var/lib/vz/template/cache/debian-12-standard_12.7-1_amd64.tar.zst" ]]; then
  echo "📅 Descargando plantilla Debian 12..."
  pveam download local debian-12-standard_12.7-1_amd64.tar.zst
fi

# Crear contenedor
echo "🛠️ Creando LXC $LXC_ID..."
pct create $LXC_ID $TEMPLATE \
  --hostname Wireguard \
  --storage local \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 1 --memory 512 --rootfs local:3 \
  --password "$ROOT_PASSWORD" \
  --unprivileged 1 --features nesting=1

pct start $LXC_ID
echo "⏳ Esperando que el contenedor esté listo..."
sleep 10

# Instalar Docker, Node.js y bcrypt
echo "🐳 Instalando Docker, Node.js y bcrypt..."
pct exec $LXC_ID -- bash -c '
apt update -qq > /dev/null &&
apt install -y -qq curl git nodejs npm > /dev/null &&
curl -fsSL https://get.docker.com | sh > /dev/null &&
npm install -g bcrypt > /dev/null
'

# Generar hash bcrypt desde Node.js
WEB_PASSWORD_HASH=$(pct exec "$LXC_ID" -- node -e "require('bcrypt').hash('$WEB_PASSWORD', 12).then(h => console.log(h))")

# Configurar WG-Easy con docker-compose.yml
echo "🔧 Configurando Wireguard..."
pct exec $LXC_ID -- bash -c "
mkdir -p /root/wireguard &&
cat > /root/wireguard/docker-compose.yml <<EOF
volumes:
  etc_wireguard:

services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    environment:
      - LANG=es
      - WG_HOST=$WG_HOST
      - PASSWORD_HASH=$WEB_PASSWORD_HASH
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

# Obtener IP local del contenedor
LXC_LOCAL_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')

# Mostrar información final
echo -e "\n🚀 Configuración completada\n"
echo "📦 ID Contenedor LXC: $LXC_ID"
echo ""
echo "🌐 Accede a WG-Easy desde:"
echo "   👉 Local:   http://$LXC_LOCAL_IP:51821"
echo "   🌍 Remoto:  https://$WG_HOST:51821"
echo ""
echo "📢 IMPORTANTE: redirige el puerto 51820/udp en tu router hacia la IP local $LXC_LOCAL_IP"

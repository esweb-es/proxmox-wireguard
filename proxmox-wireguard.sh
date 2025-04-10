#!/bin/bash
set -euo pipefail

# ================================================
# Solicitar datos
# ================================================
read -rp "➞️  IP/Dominio para WG_HOST: " WG_HOST
read -rp "🔐 PASSWORD_HASH (ver readme): " PASSWORD_HASH
read -rsp "🔑 Contraseña root del contenedor LXC: " ROOT_PASSWORD
echo

# ================================================
# Configuración base
# ================================================
LXC_ID=$(pvesh get /cluster/nextid)
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"

if [[ ! -f "/var/lib/vz/template/cache/debian-12-standard_12.7-1_amd64.tar.zst" ]]; then
  echo "📥 Descargando plantilla Debian 12..."
  pveam download local debian-12-standard_12.7-1_amd64.tar.zst
fi

echo "🛠️ Creando LXC $LXC_ID..."
pct create "$LXC_ID" "$TEMPLATE" \
  --hostname wg-easy \
  --storage local \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 1 --memory 512 --rootfs local:3 \
  --password "$ROOT_PASSWORD" \
  --unprivileged 1 --features nesting=1

pct start "$LXC_ID"
echo "⏳ Esperando que el contenedor esté listo..."
sleep 10

# ================================================
# Instalar Docker
# ================================================
echo "🐳 Instalando Docker..."
pct exec "$LXC_ID" -- bash -c '
apt update -qq && apt install -y -qq curl git ca-certificates >/dev/null
curl -fsSL https://get.docker.com | sh >/dev/null
'

# ================================================
# Configurar WG-Easy
# ================================================
echo "🔧 Configurando WG-Easy..."
pct exec "$LXC_ID" -- bash -c "
mkdir -p /root/wireguard
cat > /root/wireguard/docker-compose.yml <<EOF
version: '3.8'
volumes:
  etc_wireguard:

services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    environment:
      - LANG=es
      - WG_HOST=$WG_HOST
      - PASSWORD_HASH=$PASSWORD_HASH
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

# ================================================
# Mostrar IP y datos finales
# ================================================
LXC_LOCAL_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')

echo -e "\n🚀 WG-Easy desplegado correctamente\n"
echo "🔐 Usuario: admin"
echo "📦 LXC ID: $LXC_ID"
echo ""
echo "🌐 Accede a WG-Easy:"
echo "   👉 Local:   http://$LXC_LOCAL_IP:51821"
echo "   🌍 Remoto:  https://$WG_HOST:51821"
echo ""
echo "📢 IMPORTANTE: redirige el puerto 51820/udp hacia la IP local $LXC_LOCAL_IP"

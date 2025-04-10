#!/bin/bash
set -euo pipefail

# Solicitar datos básicos
read -rp "➞️  IP/Dominio para WG_HOST: " WG_HOST
read -rp "🔐 Pega aquí el PASSWORD_HASH (bcrypt generado en https://bcrypt-generator.com): " PASSWORD_HASH
read -rsp "🔑 Contraseña root del contenedor LXC: " ROOT_PASSWORD
echo

# Configuración
LXC_ID=$(pvesh get /cluster/nextid)
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"

# Verificar plantilla
if [[ ! -f "/var/lib/vz/template/cache/debian-12-standard_12.7-1_amd64.tar.zst" ]]; then
  echo "📦 Descargando plantilla Debian 12..."
  pveam download local debian-12-standard_12.7-1_amd64.tar.zst
fi

# Crear contenedor
echo "🛠️ Creando LXC $LXC_ID..."
pct create $LXC_ID $TEMPLATE \
  --hostname wg-easy \
  --storage local \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 1 --memory 512 --rootfs local:3 \
  --password "$ROOT_PASSWORD" \
  --unprivileged 1 --features nesting=1 >/dev/null

pct start $LXC_ID
echo "⏳ Esperando que el contenedor arranque..."
sleep 10

# Instalar Docker
echo "🐳 Instalando Docker..."
pct exec $LXC_ID -- bash -c '
apt update -qq >/dev/null && apt install -y -qq curl git >/dev/null
curl -fsSL https://get.docker.com | sh >/dev/null
'

# Crear docker-compose.yml con PASSWORD_HASH
echo "🔧 Configurando WG-Easy..."
pct exec $LXC_ID -- bash -c "
mkdir -p /root/wireguard
cat > /root/wireguard/docker-compose.yml <<EOF
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

# Mostrar información final
LXC_LOCAL_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
echo -e "\n✅ WG-Easy desplegado correctamente\n"
echo "🌐 Interfaz local:   http://$LXC_LOCAL_IP:51821"
echo "🌍 Interfaz remota:  https://$WG_HOST:51821"
echo "👤 Usuario: admin"
echo "🔐 Contraseña: (la que generaste en bcrypt)"
echo "📦 Contenedor LXC ID: $LXC_ID"
echo "📢 Redirige el puerto 51820/UDP desde tu router a $LXC_LOCAL_IP"

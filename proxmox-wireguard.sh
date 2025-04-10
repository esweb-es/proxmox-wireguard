#!/bin/bash
set -euo pipefail

# Solicitar datos básicos
read -rp "➡️  IP/Dominio para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña web: " WEB_PASSWORD
echo
read -rsp "🔑 Contraseña root LXC: " ROOT_PASSWORD
echo

# Configuración
LXC_ID=$(pvesh get /cluster/nextid)
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"

# Verificar si la plantilla existe en local
if [[ ! -f "/var/lib/vz/template/cache/debian-12-standard_12.7-1_amd64.tar.zst" ]]; then
  echo "📥 Descargando plantilla Debian 12..."
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
  --unprivileged 1 --features nesting=1

pct start $LXC_ID
echo "⏳ Esperando que el contenedor esté listo..."
sleep 10

# Instalar Docker
echo "🐳 Instalando Docker..."
pct exec $LXC_ID -- bash -c '
apt update && apt install -y curl git
curl -fsSL https://get.docker.com | sh
'

# Configurar WG-Easy
echo "🔧 Configurando WG-Easy..."
pct exec $LXC_ID -- bash -c "
mkdir -p /root/wireguard
cat > /root/wireguard/docker-compose.yml <<EOF
version: '3'
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy:v14
    container_name: wg-easy
    ports:
      - '51820:51820/udp'
      - '51821:51821/tcp'
    environment:
      - WG_HOST=$WG_HOST
      - PASSWORD=$WEB_PASSWORD
    volumes:
      - etc_wireguard:/etc/wireguard
      - /lib/modules:/lib/modules:ro
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
    restart: unless-stopped
volumes:
  etc_wireguard:
EOF
cd /root/wireguard && docker compose up -d
"

# Mostrar información
echo -e "\n✅ Configuración completada\n"
echo "URL Administración: https://$WG_HOST:51821"
echo "Contraseña Web: $WEB_PASSWORD"
echo "ID Contenedor LXC: $LXC_ID"
echo "Puerto WireGuard: 51820/udp"
echo "Contraseña root LXC: $ROOT_PASSWORD"

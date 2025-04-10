#!/bin/bash
set -euo pipefail

# ➞️ Datos fijos
WG_HOST="vpn.tudominio.com"
PASSWORD_HASH='$2y$12$ZzWXY6vTK7Gp1yRPyyVQt.JZJK4sUeqqRvYv6ASjYDiWD1LRaoxzu' # Contraseña: admin
ROOT_PASSWORD="adminroot"

# ➞️ Crear ID y plantilla
LXC_ID=$(pvesh get /cluster/nextid)
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
TEMPLATE_CACHE="/var/lib/vz/template/cache/$(basename "$TEMPLATE")"

if [[ ! -f "$TEMPLATE_CACHE" ]]; then
  echo "📥 Descargando plantilla Debian 12..."
  pveam download local $(basename "$TEMPLATE")
fi

# ➞️ Crear contenedor
echo "🛠️ Creando contenedor LXC $LXC_ID..."
pct create "$LXC_ID" "$TEMPLATE" \
  --hostname wg-easy \
  --storage local \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 1 --memory 512 --rootfs local:3 \
  --password "$ROOT_PASSWORD" \
  --unprivileged 1 --features nesting=1 >/dev/null

pct start "$LXC_ID"
echo "⏳ Inicializando contenedor..."
sleep 10

# ➞️ Instalar Docker
echo "🐳 Instalando Docker..."
pct exec "$LXC_ID" -- bash -c "
apt update -qq >/dev/null && apt install -y -qq curl >/dev/null
curl -fsSL https://get.docker.com | sh >/dev/null
"

# ➞️ Generar docker-compose.yml
echo "🔧 Configurando WG-Easy..."
pct exec "$LXC_ID" -- bash -c "
mkdir -p /root/wireguard && cd /root/wireguard
cat > docker-compose.yml <<EOF
version: '3'
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
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

volumes:
  etc_wireguard:
EOF
docker compose up -d >/dev/null
"

# ➞️ Mostrar acceso
LXC_LOCAL_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')
echo ""
echo "✅ ¡Instalación completa!"
echo "🌐 Accede localmente: http://$LXC_LOCAL_IP:51821"
echo "🌍 Accede externamente: https://$WG_HOST:51821"
echo "🔐 Usuario: admin"
echo "🔐 Contraseña: admin"
echo "📦 Contenedor LXC ID: $LXC_ID"
echo "📢 Redirige el puerto 51820/udp hacia: $LXC_LOCAL_IP"


#!/bin/bash
set -euo pipefail

# ================================================
# Solicitar datos al usuario
# ================================================
read -rp "➡️  IP pública o dominio para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña para la interfaz web: " WEB_PASSWORD
echo
read -rsp "🔑 Contraseña root para el contenedor LXC: " ROOT_PASSWORD
echo

# ================================================
# Configuración general
# ================================================
LXC_ID=$(pvesh get /cluster/nextid)
TEMPLATE="local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
HOSTNAME="wg-easy"

# ================================================
# Verificar plantilla
# ================================================
if [[ ! -f "/var/lib/vz/template/cache/debian-12-standard_12.7-1_amd64.tar.zst" ]]; then
  echo "📥 Descargando plantilla Debian 12..."
  pveam update
  pveam download local debian-12-standard_12.7-1_amd64.tar.zst
fi

# ================================================
# Crear contenedor
# ================================================
echo "🛠️ Creando contenedor LXC $LXC_ID..."
pct create $LXC_ID $TEMPLATE \
  --hostname "$HOSTNAME" \
  --storage local \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 1 \
  --memory 512 \
  --rootfs local:3 \
  --password "$ROOT_PASSWORD" \
  --unprivileged 1 \
  --features nesting=1

pct start $LXC_ID
echo "⏳ Esperando a que el contenedor inicie..."
sleep 10

# ================================================
# Instalar Docker
# ================================================
echo "🐳 Instalando Docker dentro del contenedor..."
pct exec $LXC_ID -- bash -c '
apt update &&
apt install -y curl git ca-certificates &&
curl -fsSL https://get.docker.com | sh
'

# ================================================
# Crear archivo docker-compose.yml actualizado
# ================================================
echo "🔧 Configurando WG-Easy dentro del contenedor..."
pct exec $LXC_ID -- bash -c "
mkdir -p /root/wireguard
cat > /root/wireguard/docker-compose.yml <<'EOF'
version: '3.8'

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
# Obtener IP local del contenedor
# ================================================
LXC_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')

# ================================================
# Mostrar información final
# ================================================
echo -e "\n✅ ¡WG-Easy se ha desplegado correctamente!"
echo ""
echo "🔗 Accede al panel desde:"
echo "   🌐 Local:    http://$LXC_IP:51821"
echo "   🌍 Externo:  http://$WG_HOST:51821"
echo ""
echo "🔐 Contraseña del panel web: (oculta)"
echo "🔑 Contraseña root del LXC  : (oculta)"
echo ""
echo "📢 No olvides redirigir el puerto UDP 51820 en tu router hacia la IP de Proxmox."

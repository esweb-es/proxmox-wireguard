#!/bin/bash
set -euo pipefail

# Solicitar datos básicos
read -rp "➞️  IP/Dominio para WG_HOST: " WG_HOST
while true; do
  read -rsp "🔐 Contraseña web (solo letras, números y !@#\$%&*-_): " WEB_PASSWORD
  echo
  if echo "$WEB_PASSWORD" | grep -qE '^[A-Za-z0-9!@#\$%&*_\-]+$'; then
    break
  else
    echo "❌ La contraseña contiene caracteres no permitidos. Usa solo letras, números y símbolos !@#\$%&*-_"
  fi
done
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
  --hostname wg-easy \
  --storage local \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 1 --memory 512 --rootfs local:3 \
  --password "$ROOT_PASSWORD" \
  --unprivileged 1 --features nesting=1

pct start $LXC_ID
echo "⏳ Esperando que el contenedor esté listo..."
sleep 10

# Instalar Docker, Python y bcrypt
echo "🐳 Instalando Docker y utilidades..."
pct exec $LXC_ID -- bash -c '
apt update &&
apt install -y curl git python3 python3-pip &&
curl -fsSL https://get.docker.com | sh &&
pip3 install bcrypt
'

# Generar hash bcrypt con Python (más seguro)
WEB_PASSWORD_HASH=$(pct exec "$LXC_ID" -- python3 -c "import bcrypt; print(bcrypt.hashpw(b'$WEB_PASSWORD', bcrypt.gensalt()).decode())")

# Configurar WG-Easy con docker-compose.yml
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
echo "🔐 Usuario: admin"
echo "🔐 Contraseña Web: (oculta - usando hash bcrypt)"
echo "📦 ID Contenedor LXC: $LXC_ID"
echo ""
echo "🌐 Accede a WG-Easy desde:"
echo "   👉 Local:   http://$LXC_LOCAL_IP:51821"
echo "   🌍 Remoto:  https://$WG_HOST:51821"
echo ""
echo "📢 IMPORTANTE: redirige el puerto 51820/udp en tu router hacia la IP local $LXC_LOCAL_IP"

# Verificar estado del contenedor
echo -e "\n🩺 Verificando estado del contenedor..."
WG_STATUS=$(pct exec "$LXC_ID" -- docker ps --filter name=wg-easy --format '{{.Status}}')

if [[ "$WG_STATUS" == *"Up"* ]]; then
  echo "✅ Contenedor Docker wg-easy está en ejecución."
  echo "🔐 Puedes acceder con: Usuario 'admin' y tu contraseña ingresada."
else
  echo "❌ El contenedor Docker wg-easy no se está ejecutando correctamente."
  echo "   Revisa los logs con: pct exec $LXC_ID -- docker logs wg-easy"
fi

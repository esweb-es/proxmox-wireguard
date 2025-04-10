#!/bin/bash
set -euo pipefail

# Solicitar datos básicos
read -rp "➞️  IP/Dominio para WG_HOST: " WG_HOST
while true; do
  read -rsp "🔐 Contraseña para la interfaz web: " WEB_PASSWORD
  echo
  [[ -z "$WEB_PASSWORD" ]] && echo "❌ La contraseña no puede estar vacía." && continue
  break
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
  --unprivileged 1 --features nesting=1 > /dev/null

pct start $LXC_ID > /dev/null
echo "⏳ Esperando que el contenedor esté listo..."
sleep 10

# Instalar Docker de forma silenciosa
echo "🐳 Instalando Docker..."
pct exec $LXC_ID -- bash -c '
  apt-get -qq update > /dev/null && \
  DEBIAN_FRONTEND=noninteractive apt-get -qq install -y curl ca-certificates > /dev/null && \
  install -m 0755 -d /etc/apt/keyrings && \
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
  chmod a+r /etc/apt/keyrings/docker.asc && \
  echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list && \
  apt-get -qq update > /dev/null && \
  DEBIAN_FRONTEND=noninteractive apt-get -qq install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin > /dev/null'

# Generar PASSWORD_HASH desde el host usando WG-Easy
echo "🔑 Generando hash seguro con WG-Easy..."
PASSWORD_HASH=$(docker run --rm ghcr.io/wg-easy/wg-easy wgpw "$WEB_PASSWORD")

if [[ -z "$PASSWORD_HASH" ]]; then
  echo "❌ No se pudo generar el hash. Abortando..."
  exit 1
fi

echo "✅ Hash generado correctamente"

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

# Obtener IP local del contenedor
LXC_LOCAL_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')

# Mostrar información final
echo -e "\n🚀 Configuración completada\n"
echo "🔐 Usuario: admin"
echo "🔐 Contraseña Web: (oculta - hash generado)"
echo "📦 ID Contenedor LXC: $LXC_ID"
echo "🌐 Accede a WG-Easy desde:"
echo "   👉 Local:   http://$LXC_LOCAL_IP:51821"
echo "   🌍 Remoto:  https://$WG_HOST:51821"
echo "📢 Redirige el puerto 51820/udp a $LXC_LOCAL_IP"

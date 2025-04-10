#!/bin/bash
# ================================================
# Script: wg-easy-lxc.sh
# Descripción: Despliega un contenedor LXC con WG-Easy oficial
# ================================================

set -euo pipefail

# Preguntar datos al usuario
read -p "🛡️  Contraseña de administrador para WG-Easy: " WG_PASSWORD
read -p "🔐 Contraseña de root para el contenedor: " CONTAINER_ROOT_PWD
read -p "🌍 IP pública o dominio para WG-Easy: " WG_HOST

# Obtener siguiente ID disponible
CTID=$(pvesh get /cluster/nextid)
CTNAME="Wireguard"
STORAGE="local"
HOSTNAME="wireguard"
TEMPLATE_FILE="debian-12-standard_12.2-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_FILE"
IPV4="10.42.42.42/24"
GATEWAY="10.42.42.1"
BRIDGE="vmbr0"
REPO_URL="https://github.com/wg-easy/wg-easy.git"

echo "📦 Usando ID de contenedor disponible: $CTID"

# Descargar plantilla si no existe
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "⬇️  Descargando plantilla $TEMPLATE_FILE..."
  pveam update
  pveam download local $TEMPLATE_FILE
else
  echo "✅ Plantilla Debian 12 ya está disponible."
fi

# Crear contenedor
echo "🚧 Creando contenedor LXC..."
pct create $CTID local:vztmpl/$TEMPLATE_FILE \
  -storage $STORAGE \
  -hostname $HOSTNAME \
  -password $CONTAINER_ROOT_PWD \
  -net0 name=eth0,bridge=$BRIDGE,ip=$IPV4,gw=$GATEWAY \
  -features nesting=1 \
  -unprivileged 1 \
  -cores 2 -memory 512 -swap 512 -rootfs $STORAGE:8 \
  -tags wg-easy

# Iniciar contenedor
pct start $CTID
sleep 5
echo "⏳ Arrancando contenedor $CTID..."

# Instalar Docker y Docker Compose
echo "🐳 Instalando Docker y Docker Compose..."
pct exec $CTID -- bash -c "
apt update && apt install -y curl git sudo
curl -fsSL https://get.docker.com | sh
usermod -aG docker root
apt install -y docker-compose
"

# Clonar el repositorio oficial de WG-Easy
echo "📥 Clonando WG-Easy desde $REPO_URL..."
pct exec $CTID -- git clone $REPO_URL /opt/wg-easy

# Crear archivo .env con variables
pct exec $CTID -- bash -c "echo 'PASSWORD=$WG_PASSWORD' > /opt/wg-easy/.env"
pct exec $CTID -- bash -c "echo 'WG_HOST=$WG_HOST' >> /opt/wg-easy/.env"

# Iniciar servicio
echo "🚀 Levantando WG-Easy con Docker Compose..."
pct exec $CTID -- bash -c "cd /opt/wg-easy && docker compose up -d"

# Mostrar IP local
echo "✅ Contenedor creado con éxito: $CTID"
echo "🌐 Accede a WG-Easy desde: http://10.42.42.42:51821"

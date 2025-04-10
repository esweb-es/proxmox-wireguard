#!/bin/bash
# ================================================
# Script: wg-easy-lxc.sh
# Descripción: Crea un LXC con Docker, instala WG-Easy desde el repo oficial.
# ================================================

set -euo pipefail

# Preguntar datos al usuario
read -p "🛡️  Contraseña de administrador para WG-Easy: " WG_PASSWORD
read -p "🔐 Contraseña de root para el contenedor: " CONTAINER_ROOT_PWD
read -p "🌍 IP pública o dominio para WG-Easy: " WG_HOST

# Parámetros generales
CTID=101
CTNAME="Wireguard"
STORAGE="local"
HOSTNAME="wireguard"
TEMPLATE="debian-12"
IPV4="10.42.42.42/24"
GATEWAY="10.42.42.1"
BRIDGE="vmbr0"
REPO_URL="https://github.com/wg-easy/wg-easy.git"

# Crear contenedor
echo "📦 Creando contenedor LXC ($CTID)..."
pct create $CTID local:vztmpl/${TEMPLATE}_standard_20240101.tar.zst \
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
echo "⏳ Esperando a que arranque el contenedor..."

# Instalar Docker + Docker Compose
echo "🐳 Instalando Docker y Docker Compose..."
pct exec $CTID -- bash -c "
apt update && apt install -y curl git sudo
curl -fsSL https://get.docker.com | sh
usermod -aG docker root
apt install -y docker-compose
"

# Clonar el repo oficial
echo "📥 Clonando WG-Easy desde $REPO_URL..."
pct exec $CTID -- git clone $REPO_URL /opt/wg-easy

# Crear archivo .env
pct exec $CTID -- bash -c "echo 'PASSWORD=$WG_PASSWORD' > /opt/wg-easy/.env"
pct exec $CTID -- bash -c "echo 'WG_HOST=$WG_HOST' >> /opt/wg-easy/.env"

# Levantar servicio
echo "🚀 Iniciando WG-Easy con Docker Compose..."
pct exec $CTID -- bash -c "cd /opt/wg-easy && docker compose up -d"

# Mostrar IP local
echo "✅ Contenedor $CTNAME creado e iniciado correctamente."
echo "🌐 Accede a WG-Easy desde: http://10.42.42.42:51821"

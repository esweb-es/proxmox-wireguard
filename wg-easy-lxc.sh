#!/usr/bin/env bash

set -eo pipefail

CPU="2"
RAM="512"
DISK="4"
STORAGE="local-lvm"
BRIDGE="vmbr0"
GIT_REPO="https://github.com/esweb-es/wg-easy-deploy.git"
REPO_DIR="/opt/wg-easy"
IMAGE="ghcr.io/wg-easy/wg-easy:v14"

read -rp "🛡️  Contraseña WG-Easy (admin web): " WG_PASSWORD
read -rp "🌍 Dominio/IP pública para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña root del contenedor: " ROOT_PASSWORD
echo

CTID=$(pvesh get /cluster/nextid)
TEMPLATE=$(pveam available --section system | grep debian-12-standard | sort -r | awk '{print $2}')
[ -z "$TEMPLATE" ] && { echo "❌ No se encontró plantilla Debian 12"; exit 1; }

[ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ] && {
  echo "📦 Descargando plantilla $TEMPLATE..."
  pveam update
  pveam download local "$TEMPLATE"
}

echo "🚧 Creando contenedor LXC ID $CTID..."
pct create "$CTID" local:vztmpl/"$TEMPLATE" \
  -hostname wg-easy \
  -rootfs "$STORAGE:$DISK" \
  -storage "$STORAGE" \
  -memory "$RAM" \
  -cores "$CPU" \
  -net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
  -unprivileged 1 \
  -features nesting=1

pct start "$CTID"
sleep 5

echo "🔐 Configurando contraseña root..."
echo "root:$ROOT_PASSWORD" | lxc-attach -n "$CTID" -- chpasswd

echo "🐳 Instalando Docker y plugins..."
lxc-attach -n "$CTID" -- bash -c "
apt update
apt install -y ca-certificates curl gnupg git lsb-release software-properties-common
install -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
DISTRO=\$(lsb_release -cs)
echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$DISTRO stable\" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

echo "📥 Clonando repositorio con docker-compose..."
lxc-attach -n "$CTID" -- git clone "$GIT_REPO" "$REPO_DIR"

echo "📝 Escribiendo archivo .env..."
lxc-attach -n "$CTID" -- bash -c "echo WG_HOST=$WG_HOST > $REPO_DIR/.env"
lxc-attach -n "$CTID" -- bash -c "echo WG_PASSWORD=$WG_PASSWORD >> $REPO_DIR/.env"

echo "🚀 Lanzando WG-Easy con Docker Compose..."
lxc-attach -n "$CTID" -- bash -c "cd $REPO_DIR && docker compose up -d"

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo
echo "✅ WG-Easy desplegado correctamente en http://$IP:51821"

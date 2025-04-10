#!/usr/bin/env bash
# ================================================
# Script: wg-easy-lxc.sh
# Descripción: Despliega un contenedor LXC con WG-Easy oficial (v12)
# ================================================

set -euo pipefail

APP="WG-Easy (WireGuard UI)"
var_cpu="2"
var_ram="512"
var_disk="4"
var_unprivileged="1"
BRIDGE="vmbr0"
STORAGE="local-lvm"

# ========================
# Preguntas al usuario
# ========================
read -rp "🛡️  Contraseña de administrador para WG-Easy: " WG_PASSWORD
read -rp "🌍 Dominio o IP pública para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña del usuario root para el contenedor: " ROOT_PASSWORD
echo

# ========================
# Obtener CTID y plantilla
# ========================
CTID=$(pvesh get /cluster/nextid)
echo "📦 Usando CTID disponible: $CTID"

TEMPLATE=$(pveam available --section system | grep debian-12-standard | sort -r | head -n1 | awk '{print $2}')

if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  echo "⬇️  Descargando plantilla $TEMPLATE..."
  pveam update
  pveam download local $TEMPLATE
else
  echo "✅ Plantilla Debian 12 ya está disponible: $TEMPLATE"
fi

# ========================
# Crear contenedor
# ========================
echo "🚧 Creando contenedor LXC $CTID..."
pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname wg-easy \
  -storage ${STORAGE} \
  -rootfs ${STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=${BRIDGE},ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

pct start $CTID
sleep 5

# ========================
# Asignar contraseña root
# ========================
echo "🔐 Estableciendo contraseña de root..."
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker y Docker Compose
# ========================
echo "🐳 Instalando Docker y Docker Compose..."
lxc-attach -n $CTID -- bash -c "
apt-get update
apt-get install -y ca-certificates curl gnupg git lsb-release apt-transport-https software-properties-common
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# Clonar y configurar WG-Easy (imagen v12)
# ========================
echo "📥 Clonando WG-Easy y configurando Docker Compose..."
lxc-attach -n $CTID -- bash -c "
git clone https://github.com/wg-easy/wg-easy.git /opt/wg-easy
cd /opt/wg-easy
echo 'PASSWORD=$WG_PASSWORD' > .env
echo 'WG_HOST=$WG_HOST' >> .env
sed -i 's|image:.*|image: ghcr.io/wg-easy/wg-easy:v15|' docker-compose.yml
docker compose up -d
"

# ========================
# Mostrar IP local
# ========================
IP_LOCAL=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo "✅ Contenedor $CTID creado correctamente"
echo "🌐 Accede a WG-Easy desde: http://$IP_LOCAL:51821"

#!/usr/bin/env bash
# ================================================
# Script: wg-easy-lxc.sh (con docker run directo)
# Descripción: Despliega un contenedor LXC con WG-Easy español sin usar docker-compose
# ================================================

set -euo pipefail

APP="WG-Easy Español"
var_cpu="2"
var_ram="512"
var_disk="4"
var_unprivileged="1"
BRIDGE="vmbr0"
STORAGE="local-lvm"
IMAGE="eswebes/wg-easy-es:latest"

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
# Instalar Docker
# ========================
echo "🐳 Instalando Docker..."
lxc-attach -n $CTID -- bash -c "
apt-get update
apt-get install -y ca-certificates curl gnupg git lsb-release software-properties-common
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
"

# ========================
# Lanzar WG-Easy con docker run
# ========================
echo "🚀 Ejecutando WG-Easy con Docker (imagen: $IMAGE)..."
lxc-attach -n $CTID -- bash -c "
docker run -d \
  --name wg-easy \
  -e PASSWORD=\"$WG_PASSWORD\" \
  -e WG_HOST=\"$WG_HOST\" \
  -v /etc/wireguard:/etc/wireguard \
  -v /lib/modules:/lib/modules:ro \
  -p 51820:51820/udp \
  -p 51821:51821/tcp \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --sysctl net.ipv6.conf.all.disable_ipv6=0 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  --sysctl net.ipv6.conf.default.forwarding=1 \
  --restart unless-stopped \
  $IMAGE
"

# ========================
# Mostrar IP local
# ========================
IP_LOCAL=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo "✅ Contenedor $CTID creado correctamente"
echo "🌐 Accede a WG-Easy desde: http://$IP_LOCAL:51821"

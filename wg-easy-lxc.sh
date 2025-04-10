#!/usr/bin/env bash
# ================================================
# Script: wg-easy-lxc.sh (sin docker-compose)
# Autor: esweb-es
# Descripción: Despliega WG-Easy (español) en un contenedor LXC en Proxmox
# ================================================

set -euo pipefail

APP="WG-Easy (WireGuard UI)"
var_cpu="2"
var_ram="512"
var_disk="4"
var_unprivileged="1"
BRIDGE="vmbr0"
STORAGE="local-lvm"
IMAGE="eswebes/wg-easy-es:latest"

# ========================
# Preguntas
# ========================
read -rp "🛡️  Contraseña de administrador para WG-Easy: " WG_PASSWORD
read -rp "🌍 Dominio o IP pública para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña del usuario root para el contenedor: " ROOT_PASSWORD"
echo

# ========================
# CTID y plantilla
# ========================
CTID=$(pvesh get /cluster/nextid)
TEMPLATE=$(pveam available --section system | grep debian-12-standard | sort -r | head -n1 | awk '{print $2}')

if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  echo "⬇️  Descargando plantilla $TEMPLATE..."
  pveam update
  pveam download local $TEMPLATE
fi

# ========================
# Crear contenedor
# ========================
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
# Configurar root
# ========================
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker
# ========================
lxc-attach -n $CTID -- bash -c "
apt update
apt install -y ca-certificates curl gnupg lsb-release git software-properties-common
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
"

# ========================
# Ejecutar WG-Easy (docker run)
# ========================
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
# IP final
# ========================
IP_LOCAL=$(pct exec $CTID -- hostname -I | awk '{print $1}')
echo "✅ WG-Easy desplegado correctamente"
echo "🌐 Accede desde: http://$IP_LOCAL:51821"

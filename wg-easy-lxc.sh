#!/usr/bin/env bash
# ================================================
# Script: wg-easy-lxc.sh
# Descripción: Despliega un LXC Debian con WG-Easy oficial (Docker + DHCP)
# ================================================

set -euo pipefail

APP="WG-Easy (WireGuard UI)"
var_tags="docker wireguard vpn"
var_cpu="2"
var_ram="512"
var_disk="4"
var_os="debian"
var_version="12"
var_unprivileged="1"

# ========================
# Preguntas
# ========================
read -rp "🛡️  Contraseña de administrador para WG-Easy: " WG_PASSWORD
read -rp "🌍 IP pública o dominio para WG-Easy (WG_HOST): " WG_HOST
read -rsp "🔐 Contraseña de root del contenedor: " ROOT_PASSWORD
echo

# ========================
# Fijar storage
# ========================
DETECTED_STORAGE="local-lvm"

# ========================
# Descargar plantilla si no existe
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  echo "⬇️  Descargando plantilla Debian 12..."
  pveam update
  pveam download local ${TEMPLATE}
else
  echo "✅ Plantilla Debian 12 ya está disponible."
fi

# ========================
# Crear contenedor automáticamente
# ========================
CTID=$(pvesh get /cluster/nextid)
echo "📦 Usando CTID disponible: $CTID"

pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname wg-easy \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

pct start $CTID
sleep 5

# ========================
# Asignar contraseña root
# ========================
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker y Docker Compose
# ========================
lxc-attach -n $CTID -- bash -c "
apt update && apt install -y ca-certificates curl gnupg git sudo lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# Clonar WG-Easy oficial y configurar
# ========================
lxc-attach -n $CTID -- bash -c "
git clone https://github.com/wg-easy/wg-easy.git /opt/wg-easy
cd /opt/wg-easy
echo 'PASSWORD=${WG_PASSWORD}' > .env
echo 'WG_HOST=${WG_HOST}' >> .env
docker compose up -d
"

# ========================
# Final
# ========================
echo -e "✅ WG-Easy desplegado correctamente en el contenedor #$CTID"
echo -e "🌐 Cuando obtenga IP por DHCP, accede a: http://[IP-del-contenedor]:51821"
echo -e "📥 Puedes entrar con: pct enter $CTID"

#!/usr/bin/env bash
set -euo pipefail

# Funciones
msg_ok()     { echo -e "\e[32m[OK]\e[0m $1"; }
msg_info()   { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_error()  { echo -e "\e[31m[ERROR]\e[0m $1"; }
trap 'msg_error "Se produjo un error en la línea $LINENO"' ERR

# Variables base
CTID=$(pvesh get /cluster/nextid)
HOSTNAME="Wireguard"
STORAGE="local"
DISK_SIZE="20"
MEMORY="512"
CPU="1"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

# Preguntas finales
read -rp "🌐 IP pública o dominio para WG_HOST (ej: vpn.tudominio.com): " WG_HOST
read -rsp "🔒 Contraseña para la interfaz web de WG-Easy: " WG_PASSWORD
echo
read -rsp "🔐 Contraseña root para el contenedor: " ROOT_PASSWORD
echo

# Descargar plantilla si no existe
if [[ ! -f "/var/lib/vz/template/cache/$TEMPLATE" ]]; then
  msg_info "Descargando plantilla Debian 12..."
  pveam update
  pveam download $STORAGE $TEMPLATE
fi

# Crear contenedor
msg_info "Creando contenedor LXC #$CTID..."
pct create $CTID $STORAGE:vztmpl/$TEMPLATE \
  -hostname $HOSTNAME \
  -storage $STORAGE \
  -rootfs ${STORAGE}:${DISK_SIZE} \
  -memory $MEMORY \
  -cores $CPU \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged 1 \
  -features nesting=1

pct start $CTID
sleep 5
pct exec $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# Instalar Docker
msg_info "Instalando Docker en el contenedor..."
pct exec $CTID -- bash -c "
  apt update && apt install -y \
    ca-certificates curl gnupg lsb-release apt-transport-https
  install -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
  apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
"

# Crear docker-compose.yml
msg_info "Creando docker-compose.yml..."
pct exec $CTID -- bash -c "
mkdir -p /opt/wg-easy && cd /opt/wg-easy
cat <<EOF > docker-compose.yml
version: '3'
services:
  wg-easy:
    image: weejewel/wg-easy
    container_name: wg-easy
    environment:
      - WG_HOST=${WG_HOST}
      - PASSWORD=${WG_PASSWORD}
      - WG_PORT=51820
      - WG_DEFAULT_DNS=1.1.1.1
      - WG_PERSISTENT_KEEPALIVE=25
    volumes:
      - ./config:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF
docker compose up -d
"

# Final
CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
msg_ok "WG-Easy desplegado correctamente en el contenedor #$CTID 🎉"
msg_info "🌐 Accede al panel: http://${CONTAINER_IP}:51821"

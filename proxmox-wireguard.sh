#!/usr/bin/env bash
set -euo pipefail

# ========================
# Funciones internas
# ========================
msg_ok()     { echo -e "\e[32m[OK]\e[0m $1"; }
msg_info()   { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_error()  { echo -e "\e[31m[ERROR]\e[0m $1"; }
trap 'msg_error "Se produjo un error en la línea $LINENO"' ERR

# ========================
# Variables base
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
STORAGE="local"
CTID=$(pvesh get /cluster/nextid)

# ========================
# Preguntas al usuario
# ========================
echo "⚙️  Configuración de WG-Easy:"
read -rp "🌍 Puerto para la interfaz web [51821]: " WG_PORT
WG_PORT=${WG_PORT:-51821}

read -rsp "🔒 Contraseña para el panel: " WG_PASSWORD
echo

read -rp "📛 Nombre del servidor LXC [wg-easy]: " WG_HOSTNAME
WG_HOSTNAME=${WG_HOSTNAME:-wg-easy}

read -rp "🔧 Dominio o IP pública para WG_HOST (deja vacío para auto): " CUSTOM_WG_HOST
WG_HOST=${CUSTOM_WG_HOST:-auto}

read -rsp "🔐 Contraseña para el usuario root del contenedor: " ROOT_PASSWORD
echo

# ========================
# Descargar plantilla si no existe
# ========================
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  msg_info "Descargando plantilla Debian 12..."
  pveam update
  pveam download ${STORAGE} ${TEMPLATE}
fi

# ========================
# Crear contenedor
# ========================
msg_info "Creando contenedor LXC #${CTID}..."
pct create $CTID ${STORAGE}:vztmpl/${TEMPLATE} \
  -hostname $WG_HOSTNAME \
  -storage ${STORAGE} \
  -rootfs ${STORAGE}:2 \
  -memory 512 \
  -cores 1 \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged 1 \
  -features nesting=1

pct start $CTID
sleep 5
pct exec $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker
# ========================
msg_info "Instalando Docker en el contenedor..."
pct exec $CTID -- bash -c "
  apt-get update && apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    apt-transport-https software-properties-common
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
"

# Esperar unos segundos para que docker esté disponible
sleep 3

# ========================
# Generar PASSWORD_HASH usando Docker dentro del contenedor
# ========================
msg_info "Generando PASSWORD_HASH desde el contenedor..."
HASH=$(pct exec $CTID -- bash -c "docker run --rm ghcr.io/wg-easy/wg-easy /app/bin/bcrypt-tool hash '${WG_PASSWORD}'" | tail -n 1)

# ========================
# Crear docker-compose.yml
# ========================
msg_info "Creando docker-compose.yml con el hash generado..."
pct exec $CTID -- bash -c "
  mkdir -p /opt/wg-easy && cd /opt/wg-easy
  cat <<EOF > docker-compose.yml
version: '3.8'
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    environment:
      - PASSWORD_HASH=${HASH}
      - WG_HOST=${WG_HOST}
    ports:
      - '${WG_PORT}:51821/tcp'
      - '51820:51820/udp'
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    volumes:
      - ./config:/etc/wireguard
    restart: unless-stopped
EOF
  docker compose up -d
"

# ========================
# Final
# ========================
CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
msg_ok "WG-Easy desplegado correctamente en el contenedor #$CTID 🎉"
msg_info "🌐 Accede al panel: http://${CONTAINER_IP}:${WG_PORT}"

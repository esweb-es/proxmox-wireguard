#!/usr/bin/env bash
set -euo pipefail

# === Configuración del contenedor LXC ===
CTID=$(pvesh get /cluster/nextid)
HOSTNAME="headscale"
STORAGE="local"
DISK_SIZE="4"
MEMORY="512"
CPU="1"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

# === Mensajes con colores ===
msg_ok()     { echo -e "\e[32m[\u2713]\e[0m $1"; }
msg_info()   { echo -e "\e[34m[\u2794]\e[0m $1"; }
msg_error()  { echo -e "\e[31m[\u2717]\e[0m $1"; }
trap 'msg_error "Error en la línea $LINENO"' ERR

# === Solicitar contraseña root ===
read -rsp "🔐 Contraseña root para el contenedor: " ROOT_PASSWORD
echo

# === Descargar plantilla si es necesario ===
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  msg_info "Descargando plantilla Debian 12..."
  pveam update
  pveam download ${STORAGE} ${TEMPLATE}
fi

# === Crear contenedor ===
msg_info "Creando contenedor LXC #$CTID..."
pct create $CTID ${STORAGE}:vztmpl/${TEMPLATE} \
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

# === Instalar Docker ===
msg_info "Instalando Docker..."
pct exec $CTID -- bash -c "\
  apt update && apt install -y \
    ca-certificates curl gnupg lsb-release apt-transport-https \
  && install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
  && echo \"deb [arch=\\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \\$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list \
  && apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"

# === Desplegar stack Headscale + UI ===
msg_info "Desplegando Headscale con UI..."
pct exec $CTID -- bash -c "\
  mkdir -p /opt/headscale/config /opt/headscale/db && cd /opt/headscale \
  && curl -o config/config.yaml https://raw.githubusercontent.com/juanfont/headscale/main/config-example.yaml \
  && docker run --rm headscale/headscale generate private-key > config/private.key \
  && cat <<EOF > docker-compose.yml
services:
  headscale:
    image: headscale/headscale:latest
    container_name: headscale
    volumes:
      - ./config:/etc/headscale
      - ./db:/var/lib/headscale
    ports:
      - 8080:8080
    restart: unless-stopped

  headscale-ui:
    image: ghcr.io/gurucomputing/headscale-ui:latest
    container_name: headscale-ui
    depends_on:
      - headscale
    ports:
      - 3000:80
    environment:
      - NEXT_PUBLIC_HEADSCALE_URL=http://localhost:8080
    restart: unless-stopped
EOF
  && docker compose up -d"

# === Mostrar IP de acceso ===
CONTAINER_IP=$(pct exec $CTID -- hostname -I | awk '{print $1}')
msg_ok "Headscale desplegado correctamente 🎉"
msg_info "🌐 Interfaz web: http://$CONTAINER_IP:3000"
msg_info "📡 API Headscale: http://$CONTAINER_IP:8080"

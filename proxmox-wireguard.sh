#!/bin/bash
set -euo pipefail

# ================================================
# Solicitar datos al usuario
# ================================================
read -rp "➡️  IP pública o dominio para WG_HOST: " WG_HOST
read -rp "🔐 Contraseña para la interfaz web: " WEB_PASSWORD
read -rp "🔑 Contraseña root para el contenedor LXC: " ROOT_PASSWORD

# ================================================
# Configuración general
# ================================================
TEMPLATE="local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst"
HOSTNAME="wg-easy"
STORAGE="local"
NET="name=eth0,bridge=vmbr0,ip=dhcp"
LXC_ID=$(pvesh get /cluster/nextid)
IMAGE="ghcr.io/wg-easy/wg-easy:v14"

# ================================================
# Crear contenedor LXC
# ================================================
echo "📦 Creando contenedor LXC $LXC_ID..."
pct create "$LXC_ID" "$TEMPLATE" \
  -hostname "$HOSTNAME" \
  -storage "$STORAGE" \
  -net0 "$NET" \
  -cores 1 \
  -memory 512 \
  -rootfs "$STORAGE":3 \
  -password "$ROOT_PASSWORD" \
  -features nesting=1 \
  -unprivileged 1

pct start "$LXC_ID"
echo "🚀 Contenedor iniciado."

# ================================================
# Instalar Docker y docker-compose
# ================================================
echo "🐳 Instalando Docker dentro del contenedor..."
pct exec "$LXC_ID" -- bash -c "
apt update &&
apt install -y curl ca-certificates gnupg lsb-release &&
mkdir -p /etc/apt/keyrings &&
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list &&
apt update &&
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
"

# ================================================
# Crear docker-compose.yml en el contenedor
# ================================================
echo "📄 Generando docker-compose.yml..."
pct exec "$LXC_ID" -- mkdir -p /root/wireguard
pct exec "$LXC_ID" -- bash -c "cat > /root/wireguard/docker-compose.yml" <<EOF
version: "3.8"

services:
  wg-easy:
    image: $IMAGE
    container_name: wg-easy
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    environment:
      - WG_HOST=$WG_HOST
      - PASSWORD=$WEB_PASSWORD
    volumes:
      - etc_wireguard:/etc/wireguard
      - /lib/modules:/lib/modules:ro
    restart: unless-stopped
    cap_add:
      - NET_ADMIN

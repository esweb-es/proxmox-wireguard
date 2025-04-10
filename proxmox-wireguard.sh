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
LXC_ID=$(pvesh get /cluster/nextid)
HOSTNAME="wg-easy"
STORAGE="local"
REPO="https://github.com/esweb-es/proxmox-wireguard"
REPO_DIR="/root/proxmox-wireguard"
IMAGE="ghcr.io/wg-easy/wg-easy:v14"

# ================================================
# Detectar plantilla Debian 12 más reciente (tipo + archivo)
# ================================================
TEMPLATE_LINE=$(pveam available | grep 'debian-12-standard' | sort -r | head -n1)
TEMPLATE_STORAGE=$(echo "$TEMPLATE_LINE" | awk '{print $1}')
TEMPLATE_FILE=$(echo "$TEMPLATE_LINE" | awk '{print $2}')
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_FILE"
TEMPLATE="$TEMPLATE_STORAGE:vztmpl/$TEMPLATE_FILE"

echo "🧪 Plantilla detectada: $TEMPLATE_FILE"
echo "📦 Storage de plantilla: $TEMPLATE_STORAGE"

# ================================================
# Verificar si la plantilla está descargada
# ================================================
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "📥 Plantilla no encontrada. Descargando $TEMPLATE_FILE..."
  pveam update
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILE"
else
  echo "✅ Plantilla ya disponible localmente."
fi

# ================================================
# Crear contenedor LXC
# ================================================
echo "📦 Creando contenedor LXC con ID $LXC_ID..."
pct create "$LXC_ID" "$TEMPLATE" \
  -hostname "$HOSTNAME" \
  -storage "$STORAGE" \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -cores 1 \
  -memory 512 \
  -rootfs "$STORAGE":3 \
  -password "$ROOT_PASSWORD" \
  -features nesting=1 \
  -unprivileged 1

pct start "$LXC_ID"
echo "🚀 Contenedor iniciado correctamente."

# ================================================
# Instalar Docker y clonar el repositorio
# ================================================
echo "🐳 Instalando Docker y clonando el repositorio personalizado..."
pct exec "$LXC_ID" -- bash -c "
apt update &&
apt install -y curl git ca-certificates gnupg lsb-release &&
mkdir -p /etc/apt/keyrings &&
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&
echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list &&
apt update &&
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin &&
git clone $REPO $REPO_DIR
"

# ================================================
# Crear archivo docker-compose.yml
# ================================================
echo "📄 Generando archivo docker-compose.yml..."
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
      - LANG=es_ES.UTF-8
    volumes:
      - etc_wireguard:/etc/wireguard
      - /lib/modules:/lib/modules:ro
      - /root/proxmox-wireguard/index.html:/app/public/index.html
      - /root/proxmox-wireguard/favicon.ico:/app/public/favicon.ico
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv6.conf.all.forwarding=1
      - net.ipv6.conf.default.forwarding=1

volumes:
  etc_wireguard:
EOF

# ================================================
# Lanzar contenedor con Docker Compose
# ================================================
echo "🚀 Iniciando servicio WG-Easy con Docker Compose..."
pct exec "$LXC_ID" -- bash -c "cd /root/wireguard && docker compose up -d"

# ================================================
# Mostrar información

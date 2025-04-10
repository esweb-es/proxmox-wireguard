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
TEMPLATE_FILE="debian-12-standard_12.0-1_amd64.tar.zst"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_FILE"
TEMPLATE="local:vztmpl/$TEMPLATE_FILE"
REPO="https://github.com/esweb-es/proxmox-wireguard"
REPO_DIR="/root/proxmox-wireguard"
IMAGE="ghcr.io/wg-easy/wg-easy:v14"

# ================================================
# Verificar plantilla LXC
# ================================================
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "📥 Plantilla Debian 12 no encontrada, descargando..."
  pveam update
  pveam download local "$TEMPLATE_FILE"
else
  echo "✅ Plantilla Debian 12 ya disponible."
fi

# ================================================
# Crear contenedor LXC
# ================================================
echo "📦 Creando contenedor LXC $LXC_ID..."
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
echo "🚀 Contenedor iniciado."

# ================================================
# Instalar Docker y clonar repo personalizado
# ================================================
echo "🐳 Instalando Docker y clonando repositorio..."
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
# Crear docker-compose.yml con montajes personalizados
# ================================================
echo "📄 Generando docker-compose.yml dentro del contenedor..."
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
# Lanzar WG-Easy
# ================================================
echo "🚀 Levantando WG-Easy con Docker Compose..."
pct exec "$LXC_ID" -- bash -c "cd /root/wireguard && docker compose up -d"

# ================================================
# Información final
# ================================================
LXC_IP=$(pct exec "$LXC_ID" -- hostname -I | awk '{print $1}')

echo ""
echo "✅ ¡WireGuard Easy ha sido desplegado exitosamente!"
echo ""
echo "🔗 Accede al panel web desde:"
echo "   👉 Local (Proxmox): http://$LXC_IP:51821"
echo "   🌐 Externo (redirección): http://$WG_HOST:51821"
echo ""
echo "🛡️  Contraseña del panel web: $WEB_PASSWORD"
echo "🔐 Contraseña root del contenedor (LXC $LXC_ID): $ROOT_PASSWORD"
echo ""
echo "📢 Recuerda redirigir el puerto UDP 51820 hacia la IP de tu Proxmox."

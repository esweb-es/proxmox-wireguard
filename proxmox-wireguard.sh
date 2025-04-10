#!/bin/bash
set -euo pipefail

# ================================================
# Solicitar datos al usuario con validación básica
# ================================================
while [[ -z "${WG_HOST:-}" ]]; do
  read -rp "➡️  IP pública o dominio para WG_HOST: " WG_HOST
  if [[ -z "$WG_HOST" ]]; then
    echo "❌ El campo no puede estar vacío. Por favor, inténtalo de nuevo."
  fi
done

while [[ -z "${WEB_PASSWORD:-}" ]]; do
  read -rsp "🔐 Contraseña para la interfaz web: " WEB_PASSWORD
  echo
  if [[ -z "$WEB_PASSWORD" ]]; then
    echo "❌ La contraseña no puede estar vacía. Por favor, inténtalo de nuevo."
  fi
done

while [[ -z "${ROOT_PASSWORD:-}" ]]; do
  read -rsp "🔑 Contraseña root para el contenedor LXC: " ROOT_PASSWORD
  echo
  if [[ -z "$ROOT_PASSWORD" ]]; then
    echo "❌ La contraseña no puede estar vacía. Por favor, inténtalo de nuevo."
  fi
done

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
# Detectar plantilla Debian 12 más reciente
# ================================================
echo "🔍 Buscando plantilla Debian 12 más reciente..."
TEMPLATE_LINE=$(pveam available --section system | grep 'debian-12-standard' | sort -rV | head -n1)

if [[ -z "$TEMPLATE_LINE" ]]; then
  echo "❌ No se encontró plantilla Debian 12 disponible"
  exit 1
fi

TEMPLATE_STORAGE=$(echo "$TEMPLATE_LINE" | awk '{print $1}')
TEMPLATE_FILE=$(echo "$TEMPLATE_LINE" | awk '{print $2}')
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_FILE"
TEMPLATE="$TEMPLATE_STORAGE:vztmpl/$TEMPLATE_FILE"

echo "🧪 Plantilla detectada: $TEMPLATE_FILE"
echo "📦 Storage de plantilla: $TEMPLATE_STORAGE"

# ================================================
# Verificar/descargar plantilla
# ================================================
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "📥 Descargando plantilla $TEMPLATE_FILE..."
  pveam update
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_FILE" || {
    echo "❌ Error al descargar la plantilla"
    exit 1
  }
else
  echo "✅ Plantilla ya disponible localmente."
fi

# ================================================
# Crear contenedor LXC
# ================================================
echo "📦 Creando contenedor LXC con ID $LXC_ID..."
pct create "$LXC_ID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --storage "$STORAGE" \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --cores 1 \
  --memory 512 \
  --swap 512 \
  --rootfs "$STORAGE":3 \
  --password "$ROOT_PASSWORD" \
  --features nesting=1 \
  --unprivileged 1 || {
  echo "❌ Error al crear el contenedor LXC"
  exit 1
}

echo "⏳ Iniciando contenedor..."
pct start "$LXC_ID" || {
  echo "❌ Error al iniciar el contenedor"
  exit 1
}

# Esperar a que el contenedor esté listo
echo "⏳ Esperando a que el contenedor esté listo..."
sleep 10

# ================================================
# Configurar el contenedor e instalar Docker
# ================================================
echo "🐳 Configurando el contenedor e instalando Docker..."
pct exec "$LXC_ID" -- bash -c '
set -euo pipefail

# Configurar locales
apt update && apt install -y locales
sed -i "s/^# es_ES.UTF-8/es_ES.UTF-8/" /etc/locale.gen
locale-gen es_ES.UTF-8
update-locale LANG=es_ES.UTF-8

# Instalar dependencias
export DEBIAN_FRONTEND=noninteractive
apt update && apt full-upgrade -y
apt install -y curl git ca-certificates gnupg lsb-release apt-transport-https

# Instalar Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Clonar repositorio
git clone '"$REPO"' '"$REPO_DIR"' || echo "⚠️ No se pudo clonar el repositorio, continuando..."
'

# ================================================
# Configurar WG-Easy
# ================================================
echo "📄 Configurando WG-Easy..."
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
      - $REPO_DIR/index.html:/app/public/index.html
      - $REPO_DIR/favicon.ico:/app/public/favicon.ico
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
# Iniciar WG-Easy
# ================================================
echo "🚀 Iniciando WG-Easy..."
pct exec "$LXC_ID" -- bash -c '
cd /root/wireguard
docker compose pull
docker compose up -d
'

# ================================================
# Mostrar información final
# ================================================
echo -e "\n✅ Configuración completada correctamente\n"
echo "================================================"
echo "🔌 WG-Easy Configuración:"
echo "------------------------------------------------"
echo "🌐 URL de administración: https://$WG_HOST:51821"
echo "🔑 Contraseña web: $WEB_PASSWORD"
echo "🔧 Puerto WireGuard: 51820/udp"
echo "🐧 Contenedor LXC ID: $LXC_ID"
echo "🔒 Contraseña root LXC: $ROOT_PASSWORD"
echo "================================================"
echo -e "\n⚠️ Asegúrate de tener abiertos los puertos 51820/udp y 51821/tcp en tu firewall"

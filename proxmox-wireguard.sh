#!/bin/bash
set -euo pipefail

# Colores para mensajes
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[0;33m'
AZUL='\033[0;34m'
NC='\033[0m'

# Verificar entorno
if ! command -v pct &> /dev/null; then
    echo -e "${ROJO}❌ Este script debe ejecutarse en un nodo Proxmox${NC}"
    exit 1
fi

echo -e "${AZUL}=== Instalador de WG-Easy en LXC (Proxmox) ===${NC}"
echo

# Configuración del usuario
read -p "🌐 IP estática (ej: 192.168.1.100/24) o dejar vacío para DHCP: " CT_IP
read -p "🌍 Dominio o IP pública para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña ROOT del contenedor: " ROOT_PASSWORD
echo
read -p "🔐 Pega el hash BCRYPT generado (comienza con \$2a\$): " BCRYPT_HASH
echo

# Escapar $ para uso en archivo .env
ESCAPED_HASH=$(echo "$BCRYPT_HASH" | sed 's/\$/\$\$/g')

# Generar configuración
CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="wg-easy"
if [[ -z "$CT_IP" ]]; then
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
  CT_IP_SHOW="(DHCP)"
else
  GATEWAY=$(echo "$CT_IP" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".1"}')
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$GATEWAY"
  CT_IP_SHOW=$(echo "$CT_IP" | cut -d'/' -f1)
fi

# Confirmación
echo -e "${AMARILLO}Creando LXC $CT_NAME con ID $CT_ID en $CT_IP_SHOW (${WG_HOST})...${NC}"

# Crear contenedor
pct create "$CT_ID" local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname "$CT_NAME" \
  --memory 512 \
  --cores 1 \
  --storage local \
  --rootfs local:3 \
  --net0 "$NET_CONFIG" \
  --unprivileged 0 \
  --features nesting=1 >/dev/null

pct start "$CT_ID" >/dev/null
sleep 10

# Detectar IP si es DHCP
if [[ "$CT_IP_SHOW" == "(DHCP)" ]]; then
  CT_IP_SHOW=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')
fi

# Establecer root password
pct exec "$CT_ID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Instalar Docker
pct exec "$CT_ID" -- bash -c "
apt update -qq && apt install -y curl ca-certificates gnupg lsb-release >/dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo 'deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable' > /etc/apt/sources.list.d/docker.list
apt update -qq && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
"

# Crear config
pct exec "$CT_ID" -- bash -c "
mkdir -p /opt/wg-easy
cat > /opt/wg-easy/.env <<EOF
WG_HOST=$WG_HOST
PASSWORD_HASH=$ESCAPED_HASH
WG_PORT=51820
WG_ADMIN_PORT=51821
WG_DEFAULT_ADDRESS=10.8.0.x
WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
LANG=es
EOF

cat > /opt/wg-easy/docker-compose.yml <<EOF
services:
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    env_file:
      - .env
    volumes:
      - ./data:/etc/wireguard
    ports:
      - '51820:51820/udp'
      - '51821:51821/tcp'
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF

cd /opt/wg-easy && docker compose up -d
"

# Resultado
echo -e "\n${VERDE}✅ WG-Easy instalado correctamente en el contenedor LXC ID ${CT_ID}${NC}"
echo -e "🌐 Web: http://${CT_IP_SHOW}:51821"
echo -e "🌍 Web externa: http://${WG_HOST}:51821"
echo -e "👤 Usuario: admin"
echo -e "🔐 Contraseña: la correspondiente al hash BCRYPT que pegaste"
echo -e "\n📡 Redirige el puerto UDP 51820 al contenedor (${CT_IP_SHOW})"

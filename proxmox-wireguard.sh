#!/bin/bash
set -euo pipefail

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Verificar si estamos en Proxmox
if ! command -v pct &>/dev/null; then
    echo -e "${RED}❌ Este script debe ejecutarse en un nodo Proxmox${NC}"
    exit 1
fi

echo -e "${YELLOW}⚙️ Instalador de WG-Easy (Proxmox + LXC)${NC}\n"

# Configuración
read -p "🌐 IP estática (ej: 192.168.1.100/24) o dejar vacío para DHCP: " CT_IP
read -p "🌍 Dominio o IP pública (WG_HOST): " WG_HOST
read -rsp "🔐 Contraseña ROOT del contenedor: " ROOT_PASSWORD
echo
read -rsp "🔐 Contraseña para interfaz web de WG-Easy: " WGEASY_PASSWORD
echo

# Generar hash
echo -e "${YELLOW}🔐 Generando hash BCRYPT...${NC}"
BCRYPT_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'$WGEASY_PASSWORD', bcrypt.gensalt()).decode())")
ESCAPED_HASH="${BCRYPT_HASH//\$/\$\$}"

# Lógica IP
CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="wg-easy"
if [[ -z "$CT_IP" ]]; then
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
  CT_IP_SHOW="(por DHCP)"
else
  GATEWAY=$(echo "$CT_IP" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".1"}')
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$GATEWAY"
  CT_IP_SHOW=$(echo "$CT_IP" | cut -d'/' -f1)
fi

# Crear contenedor
echo -e "${GREEN}🛠️ Creando contenedor LXC ID $CT_ID...${NC}"
pct create "$CT_ID" local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname "$CT_NAME" --memory 512 --cores 1 \
  --storage local --rootfs local:3 \
  --net0 "$NET_CONFIG" \
  --unprivileged 0 --features nesting=1 >/dev/null

# Iniciar
echo -e "${GREEN}🚀 Iniciando contenedor...${NC}"
pct start "$CT_ID" >/dev/null
sleep 10

# Obtener IP si es DHCP
if [[ "$CT_IP_SHOW" == "(por DHCP)" ]]; then
  CT_IP_SHOW=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')
fi

# Contraseña root
echo -e "${GREEN}🔐 Configurando acceso root...${NC}"
pct exec "$CT_ID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Instalar Docker
echo -e "${GREEN}🐳 Instalando Docker...${NC}"
pct exec "$CT_ID" -- bash -c '
apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg lsb-release python3-pip >/dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
'

# Crear archivos WG-Easy
echo -e "${GREEN}📦 Configurando WG-Easy...${NC}"
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

# Final
echo -e "\n${GREEN}✅ Instalación completada correctamente${NC}"
echo -e "🌐 Accede vía: http://$CT_IP_SHOW:51821 o http://$WG_HOST:51821"
echo -e "👤 Usuario: admin"
echo -e "🔐 Contraseña: (la que ingresaste)"
echo -e "📡 Puerto UDP: 51820 redirigido al contenedor"

#!/bin/bash
set -euo pipefail

# Colores para mensajes
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[0;33m'
AZUL='\033[0;34m'
NC='\033[0m' # Sin Color

# Verificar si estamos en un nodo Proxmox
if ! command -v pct &> /dev/null; then
    echo -e "${ROJO}❌ Este script debe ejecutarse en un nodo Proxmox${NC}"
    exit 1
fi

echo -e "${AZUL}=== Instalador de WireGuard Easy en Proxmox ===${NC}"
echo -e "${AMARILLO}Este script creará un contenedor LXC con WG-Easy${NC}\n"

# Solicitar configuración
read -p "🌐 IP estática (ej: 192.168.1.100/24) o dejar vacío para DHCP: " CT_IP
read -p "🌍 Dominio o IP pública para WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña ROOT del contenedor: " ROOT_PASSWORD
echo
read -p "🔐 Pega el hash bcrypt de la contraseña para WG-Easy (comienza con $2): " BCRYPT_HASH

# Escapar caracteres $ del hash
ESCAPED_HASH=$(echo "$BCRYPT_HASH" | sed 's/\$/\$\$/g')

# Configuración adicional
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

# Confirmar instalación
echo -e "\n${AMARILLO}=== Resumen de la instalación ===${NC}"
echo -e "ID del contenedor: ${AZUL}$CT_ID${NC}"
echo -e "Nombre del contenedor: ${AZUL}$CT_NAME${NC}"
echo -e "Configuración de red: ${AZUL}$NET_CONFIG${NC}"
echo -e "Host WireGuard: ${AZUL}$WG_HOST${NC}"
echo -e "\n${AMARILLO}¿Continuar con la instalación?${NC} (s/n): "
read -r CONFIRMAR
if [[ ! "$CONFIRMAR" =~ ^[Ss]$ ]]; then
    echo -e "${ROJO}Instalación cancelada${NC}"
    exit 0
fi

# Crear contenedor
echo -e "\n${VERDE}🛠️ Creando contenedor LXC ID $CT_ID...${NC}"
pct create "$CT_ID" local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname "$CT_NAME" \
  --memory 512 \
  --cores 1 \
  --storage local \
  --rootfs local:3 \
  --net0 "$NET_CONFIG" \
  --unprivileged 0 \
  --features nesting=1 >/dev/null

# Iniciar contenedor
echo -e "${VERDE}🚀 Iniciando contenedor...${NC}"
pct start "$CT_ID" >/dev/null
echo -e "${AMARILLO}Esperando a que el contenedor esté listo...${NC}"
sleep 15

# Detectar IP real si está en DHCP
if [[ "$CT_IP_SHOW" == "(por DHCP)" ]]; then
  CT_IP_SHOW=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')
  if [[ -z "$CT_IP_SHOW" ]]; then
    sleep 10
    CT_IP_SHOW=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')
  fi
fi

# Configurar contraseña root
echo -e "${VERDE}🔐 Configurando acceso root...${NC}"
pct exec "$CT_ID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Instalar Docker
echo -e "${VERDE}🐳 Instalando Docker...${NC}"
pct exec "$CT_ID" -- bash -c '
apt-get -qq update >/dev/null
apt-get -qq install -y ca-certificates curl gnupg lsb-release >/dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
apt-get -qq update >/dev/null
apt-get -qq install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
'

# Crear configuración de WG-Easy
echo -e "${VERDE}📦 Configurando WG-Easy...${NC}"
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

# Mostrar resumen
echo -e "\n${VERDE}✅ Instalación completada${NC}"
echo -e "\n${AZUL}=== DATOS DE ACCESO ===${NC}"
echo -e "🆔 Contenedor ID: ${VERDE}$CT_ID${NC}"
echo -e "💻 Acceso: ${VERDE}pct enter $CT_ID${NC}"
echo -e "🔐 Usuario root: ${VERDE}contraseña ingresada${NC}"
echo -e "\n🌐 Interfaz web: ${VERDE}http://$CT_IP_SHOW:51821${NC}"
echo -e "🌍 Desde internet: ${VERDE}http://$WG_HOST:51821${NC}"
echo -e "👤 Usuario: ${VERDE}admin${NC}"
echo -e "🔐 Contraseña: ${VERDE}la que hasheaste e ingresaste${NC}"
echo -e "\n📡 Puerto WireGuard: ${VERDE}51820/udp${NC}"
echo -e "🚨 Asegúrate de redirigir ese puerto en tu router hacia ${VERDE}$CT_IP_SHOW${NC}"

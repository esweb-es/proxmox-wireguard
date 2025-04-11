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
read -rsp "🔐 Contraseña para la interfaz web de WG-Easy: " WGEASY_PASSWORD
echo

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

# Crear contenedor con configuración de locale
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
    echo -e "${AMARILLO}Esperando a que se asigne IP por DHCP...${NC}"
    sleep 10
    CT_IP_SHOW=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')
  fi
fi

# Configurar contraseña root
echo -e "${VERDE}🔐 Configurando acceso root...${NC}"
pct exec "$CT_ID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Configurar locale correctamente antes de cualquier otra operación
echo -e "${VERDE}🌍 Configurando locale...${NC}"
pct exec "$CT_ID" -- bash -c '
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update >/dev/null 2>&1
apt-get -qq install -y locales >/dev/null 2>&1
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "es_ES.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen >/dev/null 2>&1
echo "export LANG=es_ES.UTF-8" > /etc/profile.d/locale.sh
echo "export LC_ALL=es_ES.UTF-8" >> /etc/profile.d/locale.sh
chmod +x /etc/profile.d/locale.sh
echo "LANG=es_ES.UTF-8" > /etc/default/locale
echo "LC_ALL=es_ES.UTF-8" >> /etc/default/locale
'

# Instalar Docker con configuración de locale
echo -e "${VERDE}🐳 Instalando Docker...${NC}"
pct exec "$CT_ID" -- bash -c '
source /etc/profile.d/locale.sh
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update >/dev/null 2>&1
apt-get -qq install -y ca-certificates curl gnupg lsb-release >/dev/null 2>&1
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
apt-get -qq update >/dev/null 2>&1
apt-get -qq install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null 2>&1
'

# Crear entorno WG-Easy con script Python para generar el hash
echo -e "${VERDE}📦 Configurando WG-Easy...${NC}"

# Crear un script Python en el contenedor para generar el hash y configurar WG-Easy
pct exec "$CT_ID" -- bash -c "cat > /root/setup-wg-easy.py << 'EOF'
#!/usr/bin/env python3
import bcrypt
import os
import sys

# Obtener la contraseña como argumento
password = sys.argv[1]

# Generar el hash bcrypt
bcrypt_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

# Escapar los caracteres $ duplicándolos para el archivo .env
escaped_hash = bcrypt_hash.replace('$', '$$')

# Crear el directorio para WG-Easy
os.makedirs('/opt/wg-easy', exist_ok=True)

# Crear el archivo .env con el hash escapado
with open('/opt/wg-easy/.env', 'w') as f:
    f.write(f'''WG_HOST={sys.argv[2]}
PASSWORD_HASH={escaped_hash}
WG_PORT=51820
WG_ADMIN_PORT=51821
WG_DEFAULT_ADDRESS=10.8.0.x
WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
LANG=es
''')

# Crear el archivo docker-compose.yml
with open('/opt/wg-easy/docker-compose.yml', 'w') as f:
    f.write('''services:
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
''')

print('Configuración completada con éxito')
EOF"

# Instalar dependencias de Python y ejecutar el script
pct exec "$CT_ID" -- bash -c "
source /etc/profile.d/locale.sh
export DEBIAN_FRONTEND=noninteractive
apt-get -qq install -y python3-pip python3-bcrypt >/dev/null 2>&1
chmod +x /root/setup-wg-easy.py
python3 /root/setup-wg-easy.py '$WGEASY_PASSWORD' '$WG_HOST'
cd /opt/wg-easy && docker compose up -d
"

# Configurar firewall básico
echo -e "${VERDE}🔒 Configurando firewall básico...${NC}"
pct exec "$CT_ID" -- bash -c '
source /etc/profile.d/locale.sh
export DEBIAN_FRONTEND=noninteractive
apt-get -qq install -y ufw >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 51820/udp
ufw allow 51821/tcp
echo "y" | ufw enable
'

# Limpiar paquetes innecesarios y archivos temporales
echo -e "${VERDE}🧹 Limpiando paquetes innecesarios...${NC}"
pct exec "$CT_ID" -- bash -c '
source /etc/profile.d/locale.sh
export DEBIAN_FRONTEND=noninteractive
rm -f /root/setup-wg-easy.py
apt-get -qq remove -y python3-pip python3-bcrypt >/dev/null 2>&1
apt-get -qq autoremove -y >/dev/null 2>&1
apt-get -qq clean >/dev/null 2>&1
'

# Resumen
echo -e "\n${VERDE}✅ Instalación completada${NC}"
echo -e "\n${AZUL}=== DATOS DE ACCESO ===${NC}"
echo -e "🆔 Contenedor ID: ${VERDE}$CT_ID${NC}"
echo -e "💻 Acceso: ${VERDE}pct enter $CT_ID${NC}"
echo -e "🔐 Usuario root: ${VERDE}contraseña ingresada${NC}"
echo -e "\n🌐 Interfaz web: ${VERDE}http://$CT_IP_SHOW:51821${NC}"
echo -e "🌍 Desde internet: ${VERDE}http://$WG_HOST:51821${NC}"
echo -e "👤 Usuario: ${VERDE}admin${NC}"
echo -e "🔐 Contraseña: ${VERDE}la contraseña que ingresaste para WG-Easy${NC}"
echo -e "\n📡 Puerto WireGuard: ${VERDE}51820/udp${NC}"
echo -e "🚨 Asegúrate de redirigir este puerto a ${VERDE}$CT_IP_SHOW${NC}"
echo -e "\n${AMARILLO}Nota: Si usas un dominio, asegúrate de que apunte a tu IP pública${NC}"
echo -e "${AMARILLO}y que los puertos 51820/udp y 51821/tcp estén abiertos en tu router.${NC}"

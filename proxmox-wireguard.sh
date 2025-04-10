#!/bin/bash
set -euo pipefail

# Verificar si estamos en Proxmox
if ! command -v pct &> /dev/null; then
    echo "Este script debe ejecutarse en un nodo Proxmox"
    exit 1
fi

# Solicitar configuración
read -p "🌐 Ingresa la IP estática para el contenedor (ej: 192.168.0.7/24): " CT_IP
read -p "🚪 Ingresa el puerto para WireGuard (predeterminado 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}
read -p "🖥️ Ingresa el puerto para la interfaz web (predeterminado 51821): " WG_ADMIN_PORT
WG_ADMIN_PORT=${WG_ADMIN_PORT:-51821}
read -rsp "🔐 Ingresa la contraseña ROOT para el contenedor: " ROOT_PASSWORD
echo
read -rsp "🔐 Ingresa la contraseña para la WEB de wg-easy: " WG_ADMIN_PASSWORD
echo

# Configuración adicional
CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="wg-easy"
CT_GW=$(echo $CT_IP | cut -d'/' -f1 | cut -d'.' -f1-3).1  # Calcula gateway automáticamente

# Crear contenedor
echo "🛠️ Creando contenedor LXC (ID: $CT_ID)..."
pct create $CT_ID local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
    --hostname $CT_NAME \
    --memory 512 \
    --cores 1 \
    --storage local \
    --rootfs local:3 \
    --net0 name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$CT_GW \
    --unprivileged 0 \
    --features nesting=1 >/dev/null

# Iniciar contenedor
echo "🚀 Iniciando contenedor..."
pct start $CT_ID >/dev/null
sleep 10

# Configurar contraseña root
echo "🔐 Configurando acceso root..."
pct exec $CT_ID -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Instalar Docker
echo "🐳 Instalando Docker..."
pct exec $CT_ID -- bash -c '
    apt-get -qq update >/dev/null
    apt-get -qq install -y ca-certificates curl gnupg >/dev/null
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get -qq update >/dev/null
    apt-get -qq install -y docker-ce docker-ce-cli containerd.io >/dev/null
'

# Configurar wg-easy
echo "🔧 Configurando wg-easy..."
pct exec $CT_ID -- bash -c "
    mkdir -p /opt/wg-easy
    cat <<EOF > /opt/wg-easy/docker-compose.yml
version: '3.8'
services:
  wg-easy:
    environment:
      - WG_HOST=$(echo $CT_IP | cut -d'/' -f1)
      - PASSWORD=$WG_ADMIN_PASSWORD
      - WG_PORT=$WG_PORT
      - WG_ADMIN_PORT=$WG_ADMIN_PORT
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
    image: weejewel/wg-easy
    container_name: wg-easy
    volumes:
      - ./data:/etc/wireguard
    ports:
      - '$WG_PORT:$WG_PORT/udp'
      - '$WG_ADMIN_PORT:$WG_ADMIN_PORT/tcp'
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF
    cd /opt/wg-easy && docker compose up -d
"

# Mostrar información de acceso
CT_IP_ONLY=$(echo $CT_IP | cut -d'/' -f1)
echo -e "\n✅ Instalación completada!"
echo -e "\n=== DATOS DE ACCESO ==="
echo -e "Contenedor LXC ID: $CT_ID"
echo -e "Acceso SSH: pct enter $CT_ID"
echo -e "Usuario: root"
echo -e "Contraseña: La que ingresaste"
echo -e "\nInterfaz web: http://$CT_IP_ONLY:$WG_ADMIN_PORT"
echo -e "Usuario web: admin"
echo -e "Contraseña web: La que ingresaste"
echo -e "\nPuerto WireGuard: $WG_PORT/udp"
echo -e "Recuerda abrir los puertos en tu firewall!"

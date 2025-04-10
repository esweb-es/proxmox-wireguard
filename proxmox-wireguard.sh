#!/bin/bash

# Script para instalar WireGuard (wg-easy) en LXC con Proxmox
# Permite personalizar las contraseñas manualmente

# Configuración básica (puedes modificar estos valores)
CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="wg-easy"
CT_IP="192.168.0.7/24"  # Cambia esta IP si es necesario
CT_GW="192.168.0.1"     # Cambia el gateway según tu red

# Solicitar contraseñas al usuario
read -rsp "🔑 Ingresa la contraseña ROOT para el contenedor: " ROOT_PASSWORD
echo
read -rsp "🔑 Ingresa la contraseña para la WEB de wg-easy: " WG_ADMIN_PASSWORD
echo

# Configuración de red y puertos
WG_PORT=51820
WG_ADMIN_PORT=51821

# Crear contenedor LXC
echo "🛠️ Creando contenedor LXC (ID: $CT_ID)..."
pct create $CT_ID local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
    --hostname $CT_NAME \
    --memory 512 \
    --cores 1 \
    --onboot 1 \
    --storage local-lvm \
    --rootfs local-lvm:2 \
    --net0 name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$CT_GW \
    --unprivileged 0 \
    --features nesting=1

# Iniciar contenedor
echo "🚀 Iniciando contenedor..."
pct start $CT_ID
sleep 10  # Esperar a que el contenedor esté listo

# Configurar contraseña root
echo "🔐 Configurando contraseña root..."
lxc-attach -n $CT_ID -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Instalar Docker
echo "🐳 Instalando Docker..."
lxc-attach -n $CT_ID -- bash -c '
    apt-get update && apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io
'

# Instalar wg-easy con tus contraseñas
echo "🔧 Configurando wg-easy..."
lxc-attach -n $CT_ID -- bash -c "
    mkdir -p /opt/wg-easy
    cat <<EOF > /opt/wg-easy/docker-compose.yml
services:
  wg-easy:
    environment:
      - WG_HOST=$(echo $CT_IP | cut -d'/' -f1)
      - PASSWORD=$WG_ADMIN_PASSWORD
      - WG_PORT=$WG_PORT
      - WG_ADMIN_PORT=$WG_ADMIN_PORT
      - LANG=es
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
EOF
    cd /opt/wg-easy && docker compose up -d
"

# Mostrar información de acceso
CT_IP_ONLY=$(echo $CT_IP | cut -d'/' -f1)
echo -e "\n✅ Instalación completada!"
echo -e "\n=== DATOS DE ACCESO ==="
echo -e "Contenedor LXC ID: $CT_ID"
echo -e "Acceso SSH: pct enter $CT_ID"
echo -e "Usuario root: root"
echo -e "Contraseña root: La que ingresaste"
echo -e "\nInterfaz web: http://$CT_IP_ONLY:$WG_ADMIN_PORT"
echo -e "Usuario web: admin"
echo -e "Contraseña web: La que ingresaste"
echo -e "\nPuerto WireGuard: $WG_PORT/udp"

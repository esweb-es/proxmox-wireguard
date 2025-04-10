#!/bin/bash

# Script mejorado para instalar WireGuard (wg-easy) en un contenedor LXC en Proxmox
# Versión corregida con manejo de errores mejorado

# Configuración
CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="wg-easy"
CT_OS="debian"
CT_OS_VERSION="12"
CT_IP="192.168.0.7/24"  # Modifica esto si necesitas otra IP
CT_GW="192.168.0.1"     # Cambia por tu gateway
CT_DNS="1.1.1.1"
CT_STORAGE="local-lvm"
CT_CPU=1
CT_RAM=512
CT_DISK=2
WG_PORT=51820
WG_ADMIN_PORT=51821

# Verificar dependencias
if ! command -v pvesh &> /dev/null; then
    echo "Este script debe ejecutarse en un nodo Proxmox"
    exit 1
fi

# Instalar dependencias si no existen
if ! command -v lxc-attach &> /dev/null; then
    apt-get update && apt-get install -y lxc
fi

# Generar contraseña segura (método alternativo)
if ! command -v openssl &> /dev/null; then
    apt-get update && apt-get install -y openssl
fi
WG_ADMIN_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-16)
ROOT_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | cut -c1-16)

# Crear contenedor
echo "Creando contenedor LXC..."
pct create $CT_ID local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
    --hostname $CT_NAME \
    --memory $CT_RAM \
    --cores $CT_CPU \
    --onboot 1 \
    --storage $CT_STORAGE \
    --rootfs $CT_STORAGE:$CT_DISK \
    --net0 name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$CT_GW \
    --nameserver $CT_DNS \
    --unprivileged 0 \
    --features nesting=1

# Iniciar contenedor
echo "Iniciando contenedor..."
pct start $CT_ID
sleep 10

# Configurar contraseña root
echo "Configurando contraseña root..."
lxc-attach -n $CT_ID -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

# Instalar Docker
echo "Instalando Docker..."
lxc-attach -n $CT_ID -- bash -c '
    apt-get update && apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
'

# Instalar wg-easy
echo "Instalando wg-easy..."
lxc-attach -n $CT_ID -- bash -c "
    mkdir -p /opt/wg-easy && cd /opt/wg-easy
    cat <<EOF > docker-compose.yml
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
      - WG_PERSISTENT_KEEPALIVE=25
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
    docker compose up -d
"

# Configurar firewall interno
echo "Configurando firewall..."
lxc-attach -n $CT_ID -- bash -c "
    apt-get install -y iptables
    iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT
    iptables -A INPUT -p tcp --dport $WG_ADMIN_PORT -j ACCEPT
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
"

# Mostrar información de acceso
CT_IP_ONLY=$(echo $CT_IP | cut -d'/' -f1)
echo ""
echo "=== INSTALACIÓN COMPLETADA ==="
echo "Contenedor ID: $CT_ID"
echo "Acceso SSH: pct enter $CT_ID"
echo "Usuario: root"
echo "Contraseña root: $ROOT_PASSWORD"
echo ""
echo "Interfaz web: http://$CT_IP_ONLY:$WG_ADMIN_PORT"
echo "Usuario web: admin"
echo "Contraseña web: $WG_ADMIN_PASSWORD"
echo ""
echo "Puerto WireGuard: $WG_PORT/udp"
echo ""
echo "Recuerda abrir los puertos $WG_PORT/udp y $WG_ADMIN_PORT/tcp en tu firewall"

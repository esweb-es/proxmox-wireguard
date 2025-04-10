#!/bin/bash
set -euo pipefail

# Verificar si estamos en Proxmox
if ! command -v pct &> /dev/null; then
    echo "Este script debe ejecutarse en un nodo Proxmox"
    exit 1
fi

# Solicitar configuración
while true; do
  read -p "🌐 Ingresa la IP estática para el contenedor (ej: 192.168.0.7/24): " CT_IP
  if [[ "$CT_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$ ]]; then
    break
  else
    echo "❌ IP inválida. Debe tener el formato 192.168.0.7/24"
  fi
done

read -p "🚪 Ingresa el puerto para WireGuard (predeterminado 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}
read -p "🖥️ Ingresa el puerto para la interfaz web (predeterminado 51821): " WG_ADMIN_PORT
WG_ADMIN_PORT=${WG_ADMIN_PORT:-51821}
read -rsp "🔐 Ingresa la contraseña ROOT para el contenedor: " ROOT_PASSWORD
echo

# Configuración adicional
CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="wg-easy"
CT_GW=$(echo $CT_IP | cut -d'/' -f1 | cut -d'.' -f1-3).1  # Calcula gateway automáticamente

# Crear contenedor
echo "🛠️ Creando contenedor LXC (ID: $CT_ID)..."
if ! pct create $CT_ID local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
    --hostname $CT_NAME \
    --memory 512 \
    --cores 1 \
    --storage local \
    --rootfs local:3 \
    --net0 name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$CT_GW \
    --unprivileged 0 \
    --features nesting=1; then
    echo "❌ Error: No se pudo crear el contenedor LXC. Verifica la plantilla, almacenamiento y configuración de red."
    exit 1
fi

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
    apt-get -qq install -y ca-certificates curl gnupg lsb-release >/dev/null
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
    apt-get -qq update >/dev/null
    apt-get -qq install -y docker-ce docker-ce-cli containerd.io >/dev/null
    echo "LANG=en_US.UTF-8" > /etc/default/locale
'

# Configurar wg-easy sin contraseña (modo abierto)
echo "🔧 Configurando wg-easy (sin contraseña)..."
pct exec $CT_ID -- bash -c "
    mkdir -p /opt/wg-easy/data
    cat <<EOF > /opt/wg-easy/docker-compose.yml
version: '3.8'
services:
  wg-easy:
    environment:
      - WG_HOST=$(echo $CT_IP | cut -d'/' -f1)
      - WG_PORT=$WG_PORT
      - WG_ADMIN_PORT=$WG_ADMIN_PORT
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
    image: weejewel/wg-easy
    container_name: wg-easy
    volumes:
      - /opt/wg-easy/data:/etc/wireguard
    ports:
      - '$WG_PORT:$WG_PORT/udp'
      - '$WG_ADMIN_PORT:$WG_ADMIN_PORT/tcp'
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
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
echo -e "(Modo sin contraseña temporalmente habilitado)"
echo -e "\nPuerto WireGuard: $WG_PORT/udp"
echo -e "Recuerda abrir los puertos en tu firewall!"

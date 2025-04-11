#!/bin/bash
set -euo pipefail

# Verificar si estamos en un nodo Proxmox
if ! command -v pct &> /dev/null; then
    echo "❌ Este script debe ejecutarse en un nodo Proxmox"
    exit 1
fi

# Solicitar datos
read -p "🌐 IP estática (ej: 192.168.1.100/24) o dejar vacío para DHCP: " CT_IP
read -p "🌍 Dominio o IP pública para WG_HOST: " WG_HOST
read -p "🚪 Puerto para WireGuard (por defecto 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}
read -p "🖥️ Puerto para interfaz web (por defecto 51821): " WG_ADMIN_PORT
WG_ADMIN_PORT=${WG_ADMIN_PORT:-51821}
read -rsp "🔐 Contraseña ROOT del contenedor: " ROOT_PASSWORD
echo
read -p "🔐 Pega el hash BCRYPT generado (debe comenzar con \$2a\$): " PASSWORD_HASH

# Configuración
CT_ID=$(pvesh get /cluster/nextid)
CT_NAME="wg-easy"
if [[ -z "$CT_IP" ]]; then
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=dhcp"
  CT_IP_ONLY="(por DHCP)"
else
  CT_GW=$(echo "$CT_IP" | cut -d'/' -f1 | cut -d'.' -f1-3).1
  CT_IP_ONLY=$(echo "$CT_IP" | cut -d'/' -f1)
  NET_CONFIG="name=eth0,bridge=vmbr0,ip=$CT_IP,gw=$CT_GW"
fi

echo "🛠️ Creando contenedor LXC ID $CT_ID..."
pct create "$CT_ID" local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst \
  --hostname "$CT_NAME" \
  --memory 512 \
  --cores 1 \
  --storage local \
  --rootfs local:3 \
  --net0 "$NET_CONFIG" \
  --unprivileged 0 \
  --features nesting=1 >/dev/null

echo "🚀 Iniciando contenedor..."
pct start "$CT_ID" >/dev/null
sleep 10

# Detectar IP si es DHCP
if [[ "$CT_IP_ONLY" == "(por DHCP)" ]]; then
  CT_IP_ONLY=$(pct exec "$CT_ID" -- hostname -I | awk '{print $1}')
fi

echo "🔐 Configurando acceso root..."
pct exec "$CT_ID" -- bash -c "echo 'root:$ROOT_PASSWORD' | chpasswd"

echo "🐳 Instalando Docker..."
pct exec "$CT_ID" -- bash -c '
apt-get -qq update >/dev/null
apt-get -qq install -y ca-certificates curl gnupg lsb-release >/dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" > /etc/apt/sources.list.d/docker.list
apt-get -qq update >/dev/null
apt-get -qq install -y docker-ce docker-ce-cli containerd.io >/dev/null
'

echo "📦 Configurando WG-Easy dentro del contenedor..."
pct exec "$CT_ID" -- bash -c "
mkdir -p /opt/wg-easy
cat > /opt/wg-easy/.env <<EOF
WG_HOST=$WG_HOST
PASSWORD_HASH=$$PASSWORD_HASH
WG_PORT=$WG_PORT
WG_ADMIN_PORT=$WG_ADMIN_PORT
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
      - $WG_PORT:$WG_PORT/udp
      - $WG_ADMIN_PORT:$WG_ADMIN_PORT/tcp
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF

cd /opt/wg-easy && docker compose up -d
"

echo -e "\n✅ Instalación completada"
echo -e "\n=== DATOS DE ACCESO ==="
echo -e "🆔 Contenedor LXC ID: $CT_ID"
echo -e "💻 Acceso: pct enter $CT_ID"
echo -e "🔐 Usuario root / contraseña: La que ingresaste"
echo -e "\n🌐 Interfaz web: http://$CT_IP_ONLY:$WG_ADMIN_PORT"
echo -e "🌍 Desde internet: http://$WG_HOST:$WG_ADMIN_PORT"
echo -e "👤 Usuario: admin"
echo -e "🔐 Contraseña: (la que generaste como hash)"
echo -e "\n📡 Puerto WireGuard: $WG_PORT/udp"
echo -e "🚨 Redirige ese puerto en tu router hacia: $CT_IP_ONLY"

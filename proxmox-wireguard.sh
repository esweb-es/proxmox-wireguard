#!/usr/bin/env bash
set -euo pipefail

# === Funciones de salida colorida ===
msg_ok()    { echo -e "\e[32m[✔]\e[0m $1"; }
msg_info()  { echo -e "\e[34m[➤]\e[0m $1"; }
msg_error() { echo -e "\e[31m[✘]\e[0m $1"; }
trap 'msg_error "Ocurrió un error en la línea $LINENO."' ERR

# === Preguntas al usuario ===
read -rp "🌍 Dominio o IP pública para WG_HOST (ej: vpn.midominio.com): " WG_HOST
read -rsp "🔐 Contraseña para acceder al panel (PASSWORD): " WG_PASSWORD
echo

# === Crear carpeta y archivo docker-compose.yml ===
msg_info "Creando estructura en /opt/wg-easy..."
mkdir -p /opt/wg-easy
cd /opt/wg-easy

cat <<EOF > docker-compose.yml
services:
  wg-easy:
    image: weejewel/wg-easy
    container_name: wg-easy
    environment:
      - WG_HOST=${WG_HOST}
      - PASSWORD=${WG_PASSWORD}
      - WG_PORT=51820
      - WG_DEFAULT_DNS=1.1.1.1
      - WG_PERSISTENT_KEEPALIVE=25
    volumes:
      - ./config:/etc/wireguard
    ports:
      - "51820:51820/udp"
      - "51821:51821/tcp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
EOF

msg_ok "Archivo docker-compose.yml generado."

# === Lanzar el contenedor ===
msg_info "Iniciando contenedor wg-easy..."
docker compose up -d

# === Mostrar IP del contenedor ===
CONTAINER_IP=$(hostname -I | awk '{print $1}')
msg_ok "WG-Easy desplegado correctamente 🎉"
msg_info "🌐 Accede al panel en: http://${CONTAINER_IP}:51821"

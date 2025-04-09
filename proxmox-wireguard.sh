#!/usr/bin/env bash
set -euo pipefail

# === Funciones de salida ===
msg_ok()    { echo -e "\e[32m[✔]\e[0m $1"; }
msg_info()  { echo -e "\e[34m[➤]\e[0m $1"; }
msg_error() { echo -e "\e[31m[✘]\e[0m $1"; }
trap 'msg_error "Ocurrió un error en la línea $LINENO."' ERR

# === Preguntar al usuario ===
read -rp "🌍 Dominio o IP pública para WG_HOST (ej: vpn.tudominio.com): " WG_HOST
read -rsp "🔐 Contraseña para el panel web: " WG_PASSWORD
echo

# === Crear estructura ===
msg_info "Creando carpeta /opt/wg-easy y archivo docker-compose.yml..."
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

msg_ok "docker-compose.yml generado correctamente."

# === Ejecutar WG-Easy (con compatibilidad para V1 y V2) ===
msg_info "Lanzando WG-Easy con Docker Compose..."
if command -v docker-compose &>/dev/null; then
    docker-compose up -d    # V1 (formato tradicional)
elif docker compose version &>/dev/null; then
    docker compose up -d    # V2 (nuevo formato integrado)
else
    msg_error "No se encontró docker-compose instalado. Instálalo primero."
    exit 1
fi

# === Mostrar acceso final ===
CONTAINER_IP=$(hostname -I | awk '{print $1}')
msg_ok "WG-Easy está en marcha 🚀"
msg_info "🌐 Accedé al panel en: http://${CONTAINER_IP}:51821"

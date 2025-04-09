#!/usr/bin/env bash
set -euo pipefail

# === Colores y funciones de salida ===
msg_ok() { echo -e "\e[32m[✔]\e[0m $1"; }
msg_info() { echo -e "\e[34m[➤]\e[0m $1"; }
msg_error() { echo -e "\e[31m[✘]\e[0m $1"; exit 1; }
trap 'msg_error "Error en línea $LINENO. Revisa los logs."' ERR

# === Verificar dependencias ===
check_dependencies() {
    if ! command -v docker &>/dev/null; then
        msg_info "Instalando Docker..."
        curl -fsSL https://get.docker.com | sh || msg_error "Falló la instalación de Docker"
        systemctl enable --now docker
    fi

    # Verificar Docker Compose (V1 o V2)
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        msg_info "Instalando Docker Compose V2..."
        mkdir -p ~/.docker/cli-plugins
        curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o ~/.docker/cli-plugins/docker-compose || msg_error "Falló la descarga"
        chmod +x ~/.docker/cli-plugins/docker-compose
    fi
}

# === Obtener configuración ===
get_config() {
    read -rp "🌍 Dominio o IP pública para WG_HOST (ej: vpn.tudominio.com): " WG_HOST
    read -rsp "🔐 Contraseña para el panel web: " WG_PASSWORD
    echo
    [ -z "$WG_HOST" ] && msg_error "Debes especificar un dominio/IP"
    [ -z "$WG_PASSWORD" ] && msg_error "La contraseña no puede estar vacía"
}

# === Instalar WG-Easy ===
install_wg_easy() {
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
      - WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
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

    msg_ok "Configuración generada"

    # Usar Docker Compose V1 o V2
    if command -v docker-compose &>/dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
}

# === Mostrar resultados ===
show_result() {
    local IP
    IP=$(hostname -I | awk '{print $1}')
    msg_ok "WG-Easy instalado correctamente 🚀"
    echo -e "
    🔑 Panel web: \e[34mhttp://${IP}:51821\e[0m
    📡 Puerto WireGuard: \e[34m51820/udp\e[0m
    🌐 Dominio configurado: \e[34m${WG_HOST}\e[0m
    "
}

# === Ejecución principal ===
main() {
    check_dependencies
    get_config
    install_wg_easy
    show_result
}

main

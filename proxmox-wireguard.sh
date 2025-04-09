#!/usr/bin/env bash

# ========================
# Funciones internas
# ========================

msg_ok() {
  echo -e "\e[32m[OK]\e[0m $1"
}

msg_info() {
  echo -e "\e[34m[INFO]\e[0m $1"
}

msg_error() {
  echo -e "\e[31m[ERROR]\e[0m $1"
}

catch_errors() {
  msg_error "Se ha producido un error en la línea $1"
  exit 1
}

trap 'catch_errors $LINENO' ERR

# ========================
# Variables
# ========================

APP="WireGuard con interfaz UI"
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"
DETECTED_STORAGE="local-lvm"

# ========================
# Preguntas al usuario
# ========================

read -rp "❓ ¿Quieres instalar WireGuard con interfaz UI? [s/n]: " INSTALL_WIREGUARD
INSTALL_WIREGUARD=${INSTALL_WIREGUARD,,}

if [[ "$INSTALL_WIREGUARD" == "s" ]]; then
  read -rp "🧑‍💻 Usuario para WireGuard UI (admin): " WGUI_USERNAME
  read -rsp "🔑 Contraseña para WireGuard UI: " WGUI_PASSWORD
  echo
fi

read -rsp "🔐 Ingresa la contraseña que tendrá el usuario root del contenedor: " ROOT_PASSWORD
echo

# ========================
# Descargar plantilla si no existe
# ========================

TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  msg_info "Descargando plantilla Debian 12..."
  pveam update
  pveam download local ${TEMPLATE}
fi

# ========================
# Crear contenedor LXC
# ========================

CTID=$(pvesh get /cluster/nextid)
msg_info "Creando el contenedor LXC con ID $CTID..."
pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname wireguard-stack \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

msg_info "Iniciando el contenedor LXC..."
pct start $CTID
sleep 5

# ========================
# Asignar contraseña root
# ========================

msg_info "Asignando contraseña al usuario root..."
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker
# ========================

msg_info "Instalando Docker en el contenedor..."
lxc-attach -n $CTID -- bash -c "
  apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
  apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# Instalar WireGuard + WireGuard-UI
# ========================

if [[ "$INSTALL_WIREGUARD" == "s" ]]; then
  msg_info "Desplegando WireGuard y WireGuard-UI..."
  lxc-attach -n $CTID -- bash -c "
    mkdir -p /opt/wireguard && cd /opt/wireguard
    cat <<EOF > docker-compose.yml
version: '3.8'
services:
  wireguard:
    image: linuxserver/wireguard:v1.0.20210914-ls6
    container_name: wireguard
    cap_add:
      - NET_ADMIN
    volumes:
      - ./config:/config
    ports:
      - \"80:5000\"          # WireGuard-UI
      - \"51820:51820/udp\" # VPN UDP Port

  wireguard-ui:
    image: ngoduykhanh/wireguard-ui:latest
    container_name: wireguard-ui
    depends_on:
      - wireguard
    cap_add:
      - NET_ADMIN
    network_mode: service:wireguard
    environment:
      - WGUI_USERNAME=${WGUI_USERNAME}
      - WGUI_PASSWORD=${WGUI_PASSWORD}
      - WGUI_MANAGE_START=true
      - WGUI_MANAGE_RESTART=true
    logging:
      driver: json-file
      options:
        max-size: 50m
    volumes:
      - ./db:/app/db
      - ./config:/etc/wireguard
EOF
    docker compose up -d
  "
  msg_ok "WireGuard y WireGuard-UI desplegados correctamente."
fi

# ========================
# Finalización
# ========================

msg_ok "🎉 Todo listo. Contenedor LXC #$CTID desplegado correctamente."
msg_info "Puedes acceder con: 'pct enter $CTID' y usar la contraseña de root que proporcionaste."

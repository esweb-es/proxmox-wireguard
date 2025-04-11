#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
APP="WireGuard con wg-easy"
var_tags="docker wireguard vpn wg-easy"
var_cpu="1"
var_ram="512"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

# ========================
# Preguntas condicionales
# ========================
read -rsp "🔐 Ingresa la contraseña que tendrá el usuario root del contenedor: " ROOT_PASSWORD
echo

read -rp "❓ ¿Quieres configurar un usuario para WireGuard? [s/n]: " CONFIGURE_USER
CONFIGURE_USER=${CONFIGURE_USER,,} # minúsculas

if [[ "$CONFIGURE_USER" == "s" ]]; then
    read -rp "👤 Ingresa el nombre del usuario de WireGuard: " WG_USER
fi

# ========================
# Fijar storage directamente
# ========================
DETECTED_STORAGE="local-lvm"

# ========================
# Descargar plantilla si no existe
# ========================
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
    pveam update
    pveam download local ${TEMPLATE}
fi

# ========================
# Crear contenedor automáticamente
# ========================
CTID=$(pvesh get /cluster/nextid)
pct create $CTID local:vztmpl/${TEMPLATE} \
    -hostname wg-easy-stack \
    -storage ${DETECTED_STORAGE} \
    -rootfs ${DETECTED_STORAGE}:${var_disk} \
    -memory ${var_ram} \
    -cores ${var_cpu} \
    -net0 name=eth0,bridge=vmbr0,ip=dhcp \
    -unprivileged ${var_unprivileged} \
    -features nesting=1

pct start $CTID
sleep 5

# ========================
# Asignar contraseña root
# ========================
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker
# ========================
lxc-attach -n $CTID -- bash -c "
    apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$(lsb_release -cs) stable\" > /etc/apt/sources.list.d/docker.list
    apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
"

# ========================
# Instalar wg-easy
# ========================
lxc-attach -n $CTID -- bash -c "
    mkdir -p /opt/wg-easy && cd /opt/wg-easy
    cat <<EOF > docker-compose.yml
version: '3'
services:
    wg-easy:
        image: weejewel/wg-easy
        container_name: wg-easy
        restart: always
        network_mode: 'host'
        environment:
            - WG_HOST=\$(hostname -I | awk '{print \$1}')
            - PASSWORD=${ROOT_PASSWORD}
        volumes:
            - ./config:/etc/wireguard
EOF
    docker compose up -d
"

if [[ "$CONFIGURE_USER" == "s" ]]; then
    lxc-attach -n $CTID -- bash -c "
        docker exec wg-easy /usr/bin/wg-easy add-client ${WG_USER}
    "
    msg_ok "✅ Usuario ${WG_USER} configurado correctamente en WireGuard."
fi

# ========================
# Final
# ========================
msg_ok "🎉 Todo listo. Contenedor LXC #$CTID desplegado correctamente."
echo -e "${INFO}${YW} Puedes acceder con: 'pct enter $CTID' y usar la contraseña de root que proporcionaste.${CL}"

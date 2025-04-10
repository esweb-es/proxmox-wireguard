#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
APP="WireGuard wg-easy"
var_tags="docker wireguard vpn"
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
# Configuración personalizable
# ========================
read -rp "🌐 Ingresa la IP estática para el contenedor (ej: 192.168.1.100/24): " CT_IP
read -rp "🚪 Ingresa el puerto para WireGuard (predeterminado 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}
read -rp "🖥️ Ingresa el puerto para la interfaz web (predeterminado 51821): " WG_ADMIN_PORT
WG_ADMIN_PORT=${WG_ADMIN_PORT:-51821}

# Generar contraseña aleatoria para la web
WG_ADMIN_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
read -rsp "🔐 Ingresa la contraseña root para el contenedor: " ROOT_PASSWORD
echo

# ========================
# Creación del contenedor
# ========================
DETECTED_STORAGE="local-lvm"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

# Descargar plantilla si no existe
if [[ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]]; then
  pveam update
  pveam download local ${TEMPLATE}
fi

# Crear contenedor
CTID=$(pvesh get /cluster/nextid)
msg_info "Creando contenedor LXC (ID: $CTID)"
pct create $CTID local:vztmpl/${TEMPLATE} \
  -hostname wg-easy \
  -storage ${DETECTED_STORAGE} \
  -rootfs ${DETECTED_STORAGE}:${var_disk} \
  -memory ${var_ram} \
  -cores ${var_cpu} \
  -net0 name=eth0,bridge=vmbr0,ip=${CT_IP} \
  -unprivileged ${var_unprivileged} \
  -features nesting=1

pct start $CTID
sleep 5

# Configurar contraseña root
lxc-attach -n $CTID -- bash -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# ========================
# Instalar Docker
# ========================
msg_info "Instalando Docker en el contenedor"
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
msg_info "Desplegando wg-easy"
lxc-attach -n $CTID -- bash -c "
  mkdir -p /opt/wg-easy && cd /opt/wg-easy
  cat <<EOF > docker-compose.yml
version: '3.8'
services:
  wg-easy:
    environment:
      - WG_HOST=\$(hostname -I | awk '{print \$1}')
      - PASSWORD=${WG_ADMIN_PASSWORD}
      - WG_PORT=${WG_PORT}
      - WG_ADMIN_PORT=${WG_ADMIN_PORT}
      - WG_DEFAULT_ADDRESS=10.8.0.x
      - WG_DEFAULT_DNS=1.1.1.1,8.8.8.8
      - WG_PERSISTENT_KEEPALIVE=25
    image: weejewel/wg-easy
    container_name: wg-easy
    hostname: wg-easy
    volumes:
      - ./data:/etc/wireguard
    ports:
      - '${WG_PORT}:${WG_PORT}/udp'
      - '${WG_ADMIN_PORT}:${WG_ADMIN_PORT}/tcp'
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

# ========================
# Configurar firewall del contenedor
# ========================
msg_info "Configurando firewall del contenedor"
lxc-attach -n $CTID -- bash -c "
  apt-get install -y iptables
  iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT
  iptables -A INPUT -p tcp --dport ${WG_ADMIN_PORT} -j ACCEPT
  iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
"

# ========================
# Mostrar información final
# ========================
CT_IP_ONLY=$(echo $CT_IP | cut -d'/' -f1)
msg_ok "✅ WireGuard wg-easy instalado correctamente"
echo -e "
${CL}${BOLD}=== DATOS DE ACCESO ===${CL}
${INFO}${YW}Contenedor ID: ${WHITE}$CTID
${INFO}${YW}Acceso SSH: ${WHITE}pct enter $CTID
${INFO}${YW}Usuario: ${WHITE}root
${INFO}${YW}Contraseña: ${WHITE}[la que ingresaste]
${INFO}${YW}Interfaz web: ${WHITE}http://${CT_IP_ONLY}:${WG_ADMIN_PORT}
${INFO}${YW}Usuario web: ${WHITE}admin
${INFO}${YW}Contraseña web: ${WHITE}${WG_ADMIN_PASSWORD}
${INFO}${YW}Puerto WireGuard: ${WHITE}${WG_PORT}/udp
${CL}
${INFO}${YW}Recuerda abrir los puertos ${WG_PORT}/udp y ${WG_ADMIN_PORT}/tcp en tu firewall${CL}
"

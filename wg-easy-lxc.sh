#!/bin/bash

# ========= CONFIG =========
CPU="2"
RAM="512"
DISK="4"
STORAGE="local-lvm"
BRIDGE="vmbr0"
IMAGE="eswebes/wg-easy-es:latest"

read -rp "🛡️  Contraseña WG-Easy: " WG_PASSWORD
read -rp "🌍 Dominio/IP pública WG_HOST: " WG_HOST
read -rsp "🔐 Contraseña root LXC: " ROOT_PASSWORD
echo

CTID=$(pvesh get /cluster/nextid)
TEMPLATE=$(pveam available --section system | grep debian-12-standard | sort -r | awk '{print $2}')
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "📦 Descargando plantilla $TEMPLATE..."
  pveam update
  pveam download local "$TEMPLATE"
fi

echo "🚧 Creando contenedor LXC ID $CTID..."
pct create "$CTID" local:vztmpl/"$TEMPLATE" \
  -hostname wg-easy \
  -rootfs "$STORAGE:$DISK" \
  -storage "$STORAGE" \
  -memory "$RAM" \
  -cores "$CPU" \
  -net0 name=eth0,bridge="$BRIDGE",ip=dhcp \
  -unprivileged 1 \
  -features nesting=1

pct start "$CTID"
sleep 5

echo "🔐 Configurando contraseña root..."
echo "root:$ROOT_PASSWORD" | lxc-attach -n "$CTID" -- chpasswd

echo "🐳 Instalando Docker..."
lxc-attach -n "$CTID" -- bash -c "
apt update
apt install -y ca-certificates curl gnupg lsb-release
install -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
DISTRO=\$(lsb_release -cs)
echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \$DISTRO stable\" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io
"

echo "🚀 Ejecutando WG-Easy en el contenedor..."
lxc-attach -n "$CTID" -- bash -c "
docker run -d --name wg-easy \
  -e PASSWORD=\"$WG_PASSWORD\" \
  -e WG_HOST=\"$WG_HOST\" \
  -v /etc/wireguard:/etc/wireguard \
  -v /lib/modules:/lib/modules:ro \
  -p 51820:51820/udp \
  -p 51821:51821/tcp \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv4.conf.all.src_valid_mark=1 \
  --restart unless-stopped \
  $IMAGE
"

IP=$(pct exec "$CTID" -- hostname -I | awk '{print $1}')
echo
echo "✅ WG-Easy desplegado exitosamente en el contenedor $CTID"
echo "🌐 Accede desde: http://$IP:51821"

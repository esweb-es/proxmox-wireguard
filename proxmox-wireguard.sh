#!/bin/bash

# Script de instalación de Docker y wg-easy en Proxmox
# Basado en el enlace proporcionado pero con mejoras y en español

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para mostrar mensajes de error
error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Función para mostrar mensajes de éxito
info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

# Función para mostrar advertencias
warning() {
    echo -e "${YELLOW}[ADVERTENCIA] $1${NC}"
}

# Verificar si el script se ejecuta como root
if [ "$(id -u)" -ne 0 ]; then
    error "Este script debe ejecutarse como root. Por favor, usa sudo."
fi

# Verificar si estamos en Proxmox
if ! grep -q "Proxmox" /etc/issue; then
    warning "Este script está diseñado para ejecutarse en Proxmox. Continuando de todos modos..."
fi

# Paso 1: Instalar Docker
info "Instalando Docker..."
apt-get update || error "Falló al actualizar paquetes."
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release || error "Falló al instalar dependencias."

# Agregar clave GPG de Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || error "Falló al agregar clave GPG de Docker."

# Agregar repositorio de Docker
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list || error "Falló al agregar repositorio de Docker."

# Instalar Docker
apt-get update || error "Falló al actualizar paquetes después de agregar repo de Docker."
apt-get install -y docker-ce docker-ce-cli containerd.io || error "Falló al instalar Docker."

# Verificar instalación de Docker
if docker --version &> /dev/null; then
    info "Docker instalado correctamente: $(docker --version)"
else
    error "Docker no se instaló correctamente."
fi

# Paso 2: Instalar wg-easy en Docker
info "Instalando wg-easy en Docker..."

# Variables configurables
WG_PORT=51820
WG_ADMIN_PORT=51821
WG_ADMIN_USER="admin"
WG_ADMIN_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
WG_ETH="eth0"

# Crear red de Docker para WireGuard
docker network create --subnet=10.2.0.0/24 wg-net || warning "No se pudo crear la red wg-net (puede que ya exista)."

# Ejecutar contenedor de wg-easy
docker run -d \
  --name=wg-easy \
  --cap-add=NET_ADMIN \
  --cap-add=SYS_MODULE \
  -e WG_HOST=$(hostname -I | awk '{print $1}') \
  -e PASSWORD=$WG_ADMIN_PASSWORD \
  -e WG_PORT=$WG_PORT \
  -e WG_ADMIN_PORT=$WG_ADMIN_PORT \
  -e WG_DEFAULT_ADDRESS=10.2.0.x \
  -e WG_DEFAULT_DNS=1.1.1.1,8.8.8.8 \
  -e WG_ALLOWED_IPS=10.2.0.0/24,0.0.0.0/0 \
  -e WG_PERSISTENT_KEEPALIVE=25 \
  -p $WG_PORT:$WG_PORT/udp \
  -p $WG_ADMIN_PORT:$WG_ADMIN_PORT/tcp \
  -v $(pwd)/wg-easy:/etc/wireguard \
  --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
  --sysctl="net.ipv4.ip_forward=1" \
  --restart unless-stopped \
  weejewel/wg-easy || error "Falló al iniciar el contenedor wg-easy."

# Mostrar información de acceso
info "wg-easy instalado correctamente!"
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} Configuración de wg-easy:${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "${YELLOW}Interfaz web:${NC} http://$(hostname -I | awk '{print $1}'):$WG_ADMIN_PORT"
echo -e "${YELLOW}Usuario:${NC} admin"
echo -e "${YELLOW}Contraseña:${NC} $WG_ADMIN_PASSWORD"
echo -e "${YELLOW}Puerto WireGuard:${NC} $WG_PORT/udp"
echo -e "${GREEN}=============================================${NC}"
echo -e "${YELLOW}Nota:${NC} Asegúrate de abrir los puertos $WG_PORT/udp y $WG_ADMIN_PORT/tcp en el firewall."
echo -e "${YELLOW}Nota:${NC} La configuración de WireGuard se guarda en: $(pwd)/wg-easy"

# Fin del script
info "Instalación completada con éxito!"

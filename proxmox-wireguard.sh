#!/bin/bash

# Script de limpieza completa para Docker y wg-easy en Proxmox
# Eliminará contenedores, imágenes, volúmenes, redes y paquetes Docker

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verificar si el script se ejecuta como root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[ERROR] Este script debe ejecutarse como root. Usa sudo.${NC}"
    exit 1
fi

echo -e "${YELLOW}[INICIO] Comenzando proceso de limpieza...${NC}"

# Paso 1: Detener y eliminar el contenedor wg-easy
echo -e "${YELLOW}[PASO 1/6] Eliminando contenedor wg-easy...${NC}"
if docker ps -a --format '{{.Names}}' | grep -q 'wg-easy'; then
    docker stop wg-easy >/dev/null 2>&1
    docker rm wg-easy >/dev/null 2>&1
    echo -e "${GREEN}Contenedor wg-easy eliminado.${NC}"
else
    echo -e "${YELLOW}No se encontró el contenedor wg-easy.${NC}"
fi

# Paso 2: Eliminar la imagen de wg-easy
echo -e "${YELLOW}[PASO 2/6] Eliminando imagen wg-easy...${NC}"
if docker images --format '{{.Repository}}' | grep -q 'weejewel/wg-easy'; then
    docker rmi weejewel/wg-easy >/dev/null 2>&1
    echo -e "${GREEN}Imagen wg-easy eliminada.${NC}"
else
    echo -e "${YELLOW}No se encontró la imagen wg-easy.${NC}"
fi

# Paso 3: Eliminar la red docker de WireGuard
echo -e "${YELLOW}[PASO 3/6] Eliminando red wg-net...${NC}"
if docker network ls --format '{{.Name}}' | grep -q 'wg-net'; then
    docker network rm wg-net >/dev/null 2>&1
    echo -e "${GREEN}Red wg-net eliminada.${NC}"
else
    echo -e "${YELLOW}No se encontró la red wg-net.${NC}"
fi

# Paso 4: Eliminar el volumen de configuración
echo -e "${YELLOW}[PASO 4/6] Eliminando datos de configuración...${NC}"
CONFIG_DIR="$(pwd)/wg-easy"
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    echo -e "${GREEN}Datos de configuración eliminados de: $CONFIG_DIR${NC}"
else
    echo -e "${YELLOW}No se encontró el directorio de configuración.${NC}"
fi

# Paso 5: Desinstalar Docker y sus dependencias
echo -e "${YELLOW}[PASO 5/6] Desinstalando Docker...${NC}"
if command -v docker &> /dev/null; then
    # Detener todos los contenedores en ejecución
    docker stop $(docker ps -aq) >/dev/null 2>&1
    
    # Eliminar todos los contenedores, imágenes, redes y volúmenes
    docker system prune -a --volumes -f >/dev/null 2>&1
    
    # Desinstalar paquetes
    apt-get purge -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
    apt-get autoremove -y >/dev/null 2>&1
    rm -rf /var/lib/docker
    rm -rf /etc/docker
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /usr/share/keyrings/docker-archive-keyring.gpg
    echo -e "${GREEN}Docker y todos sus componentes desinstalados.${NC}"
else
    echo -e "${YELLOW}Docker no estaba instalado.${NC}"
fi

# Paso 6: Limpiar configuraciones residuales
echo -e "${YELLOW}[PASO 6/6] Limpiando configuraciones residuales...${NC}"
# Eliminar reglas de firewall específicas para los puertos 51820 y 51821
if command -v ufw &> /dev/null; then
    ufw delete allow 51820/udp >/dev/null 2>&1
    ufw delete allow 51821/tcp >/dev/null 2>&1
fi

# Limpiar sysctl
sed -i '/net.ipv4.conf.all.src_valid_mark/d' /etc/sysctl.conf
sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

echo -e "${GREEN}Configuraciones residuales eliminadas.${NC}"

# Resultado final
echo -e "\n${GREEN}[COMPLETADO] ¡Limpieza realizada con éxito!${NC}"
echo -e "${YELLOW}Se han eliminado todos los componentes de Docker y wg-easy del sistema.${NC}"

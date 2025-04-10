## 🛡️ Proxmox WireGuard con WG-Easy (instalación automatizada y acceso web seguro)

Este script despliega un contenedor **LXC** en **Proxmox VE** con **Docker** y **WG-Easy**, una interfaz web moderna para administrar tu servidor **WireGuard VPN**.

Utiliza la imagen oficial:  
**`weejewel/wg-easy`**

---

## ⚙️ Características

- Despliegue completamente automatizado
- Contenedor Debian 12 sin privilegios
- Instalación de Docker y Docker Compose
- Interfaz web protegida con usuario `admin` y contraseña personalizada
- Detección automática de la IP local del contenedor
- Compatible con almacenamiento `local`
- Silencioso y limpio (sin verbosidad innecesaria)

---

## 🚀 Cómo usar

Ejecuta el siguiente comando en tu nodo **Proxmox VE** como `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/esweb-es/proxmox-wireguard/main/proxmox-wireguard.sh)"


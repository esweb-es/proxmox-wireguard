## 🛡️ Proxmox WireGuard con WG-Easy (instalación automática con hash seguro)

Este script despliega un contenedor LXC en **Proxmox VE** con **Docker** y **WG-Easy**, una interfaz web moderna para administrar tu servidor **WireGuard VPN**.

Utiliza la imagen oficial:  
**`ghcr.io/wg-easy/wg-easy`**

---

## ⚙️ Características

- Despliegue totalmente automatizado en Proxmox
- Contenedor Debian 12 sin privilegios
- Instalación de Docker + Node.js
- Generación automática del `PASSWORD_HASH` usando bcrypt
- Detección y visualización automática de la IP del contenedor
- Compatible con almacenamiento `local`

---

## 🚀 Cómo usar

Ejecuta el siguiente comando en tu nodo **Proxmox VE** como `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/esweb-es/proxmox-wireguard/main/wg-easy-lxc.sh)"

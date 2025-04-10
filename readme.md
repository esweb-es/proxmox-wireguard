## 🛡️ Proxmox WireGuard con WG-Easy (instalación automática con acceso web seguro)

Este script despliega un contenedor **LXC** en **Proxmox VE** con **Docker** y **WG-Easy**, una interfaz web moderna para administrar tu servidor **WireGuard VPN**.

Utiliza la imagen oficial:
**`ghcr.io/wg-easy/wg-easy`**

---

## ⚙️ Características

- Despliegue totalmente automatizado en Proxmox
- Contenedor Debian 12 sin privilegios
- Instalación de Docker automatizada
- Interfaz web protegida con usuario `admin` y contraseña personalizada
- Detección automática de la IP local del contenedor
- Recomendación para redirigir puertos
- Compatible con almacenamiento `local`

---

## 🚀 Cómo usar

Ejecuta el siguiente comando en tu nodo **Proxmox VE** como `root`:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/esweb-es/proxmox-wireguard/main/proxmox-wireguard.sh)"
```

---

## 🌎 Acceso a la interfaz WG-Easy

Una vez finalizado el despliegue, verás en pantalla:

- La IP local del contenedor
- El dominio o IP externa configurada
- Las credenciales de acceso:
  - **Usuario:** `admin`
  - **Contraseña:** la que hayas ingresado al iniciar el script

---

## 🔧 Requisitos

- Proxmox VE 7 u 8
- Plantilla descargada: `debian-12-standard_12.7-1_amd64.tar.zst`
- Almacenamiento disponible en `local`
- Acceso como usuario `root`

---

## 📢 Nota importante

🚧 Asegúrate de **redirigir el puerto UDP 51820** desde tu router hacia la IP local que se muestra al finalizar la instalación.

---

📄 Repositorio oficial: [esweb-es/proxmox-wireguard](https://github.com/esweb-es/proxmox-wireguard)

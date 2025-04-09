# ========================
# Preguntar si instalar WireGuard
# ========================
read -rp "❓ ¿Quieres instalar WireGuard con interfaz UI? [s/n]: " INSTALL_WIREGUARD
INSTALL_WIREGUARD=${INSTALL_WIREGUARD,,}

if [[ "$INSTALL_WIREGUARD" == "s" ]]; then
  read -rp "🧑‍💻 Usuario para WireGuard UI (admin): " WGUI_USERNAME
  read -rsp "🔑 Contraseña para WireGuard UI: " WGUI_PASSWORD
  echo
fi

# ========================
# Instalar WireGuard + WireGuard-UI
# ========================
if [[ "$INSTALL_WIREGUARD" == "s" ]]; then
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
  msg_ok "✅ WireGuard + UI desplegados correctamente"
fi

#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Configuration Variables ---
SUBDOMAIN="hermes.gholamthegreat.sbs"
TUNNEL_NAME="hermes"
PORT="8787"

echo "========================================================="
echo "   Starting Automated Hermes & Cloudflare Tunnel Setup   "
echo "========================================================="

# 1. Update system and install required packages
echo "[1/6] Updating system and installing dependencies..."
apt update && apt install -y curl git build-essential libatomic1 xz-utils

# 2. Download and install cloudflared
echo "[2/6] Installing Cloudflare Tunnel (cloudflared)..."
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb
rm cloudflared.deb

# 3. Cloudflare authentication
echo "[3/6] Please log in to your Cloudflare account:"
echo "Open the URL below in your browser and authorize your domain."
cloudflared tunnel login

# 4. Create tunnel and route DNS
echo "[4/6] Creating tunnel and routing DNS to $SUBDOMAIN ..."
cloudflared tunnel delete -f $TUNNEL_NAME >/dev/null 2>&1 || true

# Capture both stdout and stderr to parse the tunnel UUID accurately
TUNNEL_OUTPUT=$(cloudflared tunnel create $TUNNEL_NAME 2>&1)
TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -n 1)

if [ -z "$TUNNEL_ID" ]; then
    echo "Error: Failed to retrieve tunnel UUID!"
    echo "Cloudflare output:"
    echo "$TUNNEL_OUTPUT"
    exit 1
fi

echo "Created Tunnel UUID: $TUNNEL_ID"

cloudflared tunnel route dns $TUNNEL_NAME $SUBDOMAIN

# 5. Generate configuration file (config.yml)
echo "[5/6] Configuring cloudflared config file..."
mkdir -p ~/.cloudflared
cat <<EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $SUBDOMAIN
    service: http://127.0.0.1:$PORT
  - service: http_status:404
EOF

systemctl stop cloudflared >/dev/null 2>&1 || true
cloudflared service install >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared

# 6. Setup Hermes WebUI
echo "[6/6] Setting up Hermes WebUI..."
if [ ! -d "$HOME/hermes-webui" ]; then
    git clone https://github.com/nesquena/hermes-webui.git $HOME/hermes-webui
fi

cd $HOME/hermes-webui

cat <<EOF > /etc/systemd/system/hermes-webui.service
[Unit]
Description=Hermes WebUI Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$HOME/hermes-webui
ExecStart=$HOME/hermes-webui/start.sh
Restart=always
RestartSec=5
Environment=HERMES_WEBUI_BIND_HOST=127.0.0.1
Environment=PORT=$PORT

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hermes-webui
systemctl restart hermes-webui

echo "========================================================="
echo "   ✅ Installation completed successfully!               "
echo "   Access URL: https://$SUBDOMAIN                        "
echo "========================================================="

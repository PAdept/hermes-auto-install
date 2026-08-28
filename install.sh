#!/bin/bash

# خروج فوری در صورت بروز خطا
set -e

# --- تنظیمات متغیرها ---
SUBDOMAIN="hermes.gholamthegreat.sbs"
TUNNEL_NAME="hermes"
PORT="8787"

echo "========================================="
echo "   شروع نصب خودکار Hermes و Cloudflare Tunnel   "
echo "========================================="

# ۱. به‌روزرسانی سیستم و نصب ابزارهای پایه
echo "[1/6] در حال به‌روزرسانی سیستم و نصب پیش‌نیازها..."
apt update && apt install -y curl git build-essential libatomic1 xz-utils

# ۲. دانلود و نصب cloudflared
echo "[2/6] در حال نصب Cloudflare Tunnel (cloudflared)..."
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared.deb
rm cloudflared.deb

# ۳. ورود به حساب کلاودفلر
echo "[3/6] لطفاً وارد حساب Cloudflare خود شوید:"
echo "یک لینک در ادامه نمایش داده می‌شود، آن را در مرورگر باز کرده و دامنه خود را انتخاب کنید."
cloudflared tunnel login

# ۴. ساخت تونل و روت کردن DNS
echo "[4/6] در حال ایجاد تونل و تنظیم DNS روی $SUBDOMAIN ..."
# پاکسازی تونل‌های همنام قدیمی در صورت وجود
cloudflared tunnel delete -f $TUNNEL_NAME >/dev/null 2>&1 || true

# ساخت تونل جدید و دریافت UUID
TUNNEL_OUTPUT=$(cloudflared tunnel create $TUNNEL_NAME)
TUNNEL_ID=$(echo "$TUNNEL_OUTPUT" | grep -oE '[a-0-9]{8}-[a-0-9]{4}-[a-0-9]{4}-[a-0-9]{4}-[a-0-9]{12}' | head -n 1)

if [ -z "$TUNNEL_ID" ]; then
    echo "خطا در دریافت شناسه (UUID) تونل!"
    exit 1
fi

echo "شناسه تونل ایجاد شده: $TUNNEL_ID"

# اتصال ساب‌دامنه به تونل
cloudflared tunnel route dns $TUNNEL_NAME $SUBDOMAIN

# ۵. ایجاد فایل تنظیمات (config.yml)
echo "[5/6] در حال پیکربندی فایل تنظیمات cloudflared..."
mkdir -p ~/.cloudflared
cat <<EOF > ~/.cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $SUBDOMAIN
    service: http://127.0.0.1:$PORT
  - service: http_status:404
EOF

# نصب و فعال‌سازی سرویس cloudflared
systemctl stop cloudflared >/dev/null 2>&1 || true
cloudflared service install >/dev/null 2>&1 || true
systemctl daemon-reload
systemctl enable cloudflared
systemctl restart cloudflared

# ۶. نصب Hermes WebUI (در صورت عدم وجود)
echo "[6/6] در حال آماده‌سازی Hermes WebUI..."
if [ ! -d "$HOME/hermes-webui" ]; then
    git clone https://github.com/nesquena/hermes-webui.git $HOME/hermes-webui
fi

cd $HOME/hermes-webui

# ساخت سرویس systemd برای اجرای دائمی Hermes WebUI
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

echo "========================================="
echo "   ✅ نصب و راه‌اندازی با موفقیت انجام شد!   "
echo "   آدرس دسترسی شما: https://$SUBDOMAIN   "
echo "========================================="

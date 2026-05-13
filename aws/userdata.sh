#!/bin/bash
# userdata.sh — EC2 Launch Template UserData
# Bu script EC2 başladığında otomatik çalışır

set -euo pipefail

# Node.js 20 LTS kurulum
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs git

# Uygulama dizini
APP_DIR="/app/ecommerce-secure"
mkdir -p "$APP_DIR"
useradd -r -s /bin/false appuser
chown appuser:appuser "$APP_DIR"

# Kodu GitHub'dan çek
# git clone https://github.com/YOUR_USERNAME/ecommerce-secure.git "$APP_DIR"

# Secrets — AWS SSM Parameter Store'dan al (hardcoded credential YOK)
DB_HOST=$(aws ssm get-parameter \
  --name "/ecommerce/db/host" \
  --with-decryption \
  --query 'Parameter.Value' --output text)

DB_PASSWORD=$(aws ssm get-parameter \
  --name "/ecommerce/db/password" \
  --with-decryption \
  --query 'Parameter.Value' --output text)

SESSION_SECRET=$(aws ssm get-parameter \
  --name "/ecommerce/session/secret" \
  --with-decryption \
  --query 'Parameter.Value' --output text)

# .env dosyasını SSM'den oluştur
cat > "$APP_DIR/.env" <<EOF
NODE_ENV=production
PORT=3000
DB_HOST=$DB_HOST
DB_PORT=3306
DB_NAME=ecommerce_db
DB_USER=app_user
DB_PASSWORD=$DB_PASSWORD
SESSION_SECRET=$SESSION_SECRET
EOF

chmod 600 "$APP_DIR/.env"  # Sadece appuser okuyabilir
chown appuser:appuser "$APP_DIR/.env"

# npm install (production only)
cd "$APP_DIR"
sudo -u appuser npm ci --only=production

# systemd service (process manager)
cat > /etc/systemd/system/ecommerce.service <<EOF
[Unit]
Description=Secure E-Commerce Node.js App
After=network.target

[Service]
Type=simple
User=appuser
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node src/app.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ecommerce
systemctl start ecommerce

echo "✅ E-Commerce app başlatıldı"

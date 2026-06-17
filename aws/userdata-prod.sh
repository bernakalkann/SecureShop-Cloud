#!/bin/bash
set -euo pipefail

# İşletim sistemi güncellemeleri ve Node.js 20 kurulumu
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs git

# Port yönlendirme (80 -> 3000)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 3000

APP_DIR="/app/ecommerce-secure"
mkdir -p "$APP_DIR"
useradd -r -s /bin/false appuser
chown appuser:appuser "$APP_DIR"

# Kodu klonla
git clone https://github.com/bernakalkann/SecureShop-Cloud.git "$APP_DIR"

# Çevre değişkenleri (.env) dosyasını oluştur
cat > "$APP_DIR/.env" <<EOT
NODE_ENV=production
PORT=3000
DB_HOST=ecommerce-secure-db.c14gkm6ik4ev.eu-central-1.rds.amazonaws.com
DB_PORT=3306
DB_NAME=ecommerce_db
DB_USER=admin
DB_PASSWORD=SecureEcomPass123!
SESSION_SECRET=b7310a40b787aa04c4d2aa395648a373091dbf0c3211f1265ff3789a98094082
EOT

chown appuser:appuser "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"

# Bağımlılıkları kur
cd "$APP_DIR"
sudo -u appuser npm ci --only=production

# Veritabanı tablolarını oluştur
sudo -u appuser DB_HOST=ecommerce-secure-db.c14gkm6ik4ev.eu-central-1.rds.amazonaws.com DB_USER=admin DB_PASSWORD=SecureEcomPass123! DB_NAME=ecommerce_db node initialize_db.js

# Systemd Servisi Oluştur
cat > /etc/systemd/system/ecommerce.service <<EOT
[Unit]
Description=Secure E-Commerce Node.js App
After=network.target

[Service]
Type=simple
User=appuser
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node src/app.js
Restart=always
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOT

systemctl daemon-reload
systemctl enable ecommerce
systemctl start ecommerce
echo "✅ E-Commerce uygulaması başlatıldı"

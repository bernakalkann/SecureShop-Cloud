#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# setup-aws.sh — AWS Altyapı Kurulum Scripti (Geliştirilmiş & Hızlı Sürüm)
# Proje 4: Güvenli E-Ticaret Altyapısı (Defense in Depth)
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail  # Hata durumunda dur

# Bölgeyi otomatik al veya ortam değişkenini kullan
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
PROJECT="ecommerce-secure"
ADMIN_IP=$(curl -s https://api.ipify.org)/32  # Mevcut IP'yi otomatik al

# Şifreler ve Sırlar
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-SecureEcomPass123!}"
SESSION_SECRET="${SESSION_SECRET:-$(openssl rand -hex 32)}"

echo "╔══════════════════════════════════════════════╗"
echo "║   AWS Güvenli E-Ticaret Altyapı Kurulumu    ║"
echo "╚══════════════════════════════════════════════╝"
echo "Bölge: $AWS_REGION | Admin IP: $ADMIN_IP"
echo "RDS Master Password: $DB_ROOT_PASSWORD"
echo ""

echo "🔍 En güncel Amazon Linux 2023 AMI adresi aranıyor..."
AMI_ID=$(aws ec2 describe-images \
  --region "$AWS_REGION" \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
  --query "Images[0].ImageId" \
  --output text)
echo "✅ Seçilen AMI: $AMI_ID"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 1: VPC ve Subnets
# ─────────────────────────────────────────────────────────────────────────
echo "📦 [1/6] VPC ve Subnet Oluşturuluyor..."

VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region "$AWS_REGION" \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$AWS_REGION"
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="${PROJECT}-vpc" --region "$AWS_REGION"
echo "  ✅ VPC: $VPC_ID"

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$AWS_REGION" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$AWS_REGION"
echo "  ✅ Internet Gateway: $IGW_ID"

# Public Subnet (ALB için) — AZ-a
SUBNET_PUBLIC=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$SUBNET_PUBLIC" --tags Key=Name,Value="${PROJECT}-public-1a" --region "$AWS_REGION"

# Public Subnet — AZ-b (ALB en az 2 AZ gerektirir)
SUBNET_PUBLIC_B=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.4.0/24 \
  --availability-zone "${AWS_REGION}b" \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$SUBNET_PUBLIC_B" --tags Key=Name,Value="${PROJECT}-public-1b" --region "$AWS_REGION"

# Private Subnet — App Tier (AZ-a)
SUBNET_APP=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$SUBNET_APP" --tags Key=Name,Value="${PROJECT}-app-private-1a" --region "$AWS_REGION"

# Private Subnet — DB Tier (AZ-a ve AZ-b, Multi-AZ için)
SUBNET_DB_A=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.3.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' --output text)

SUBNET_DB_B=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.5.0/24 \
  --availability-zone "${AWS_REGION}b" \
  --region "$AWS_REGION" \
  --query 'Subnet.SubnetId' --output text)

aws ec2 create-tags --resources "$SUBNET_DB_A" --tags Key=Name,Value="${PROJECT}-db-private-1a" --region "$AWS_REGION"
aws ec2 create-tags --resources "$SUBNET_DB_B" --tags Key=Name,Value="${PROJECT}-db-private-1b" --region "$AWS_REGION"

echo "  ✅ Subnets oluşturuldu (Public/App/DB)"

# Route Table — Public
RT_PUBLIC=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RT_PUBLIC" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID" \
  --region "$AWS_REGION"
aws ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC" --region "$AWS_REGION"
aws ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC_B" --region "$AWS_REGION"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 2: Security Groups (Least Privilege)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "🔒 [2/6] Security Groups Yapılandırılıyor (Least Privilege)..."

# sg-bastion: Sadece admin SSH erişimi
SG_BASTION=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-bastion" \
  --description "Bastion Host - Admin SSH only" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_BASTION" \
  --protocol tcp --port 22 \
  --cidr "$ADMIN_IP" \
  --region "$AWS_REGION"
echo "  ✅ sg-bastion ($SG_BASTION) — SSH: $ADMIN_IP only"

# sg-alb: İnternet'ten 80
SG_ALB=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-alb" \
  --description "ALB - Public HTTP" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ALB" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION"
echo "  ✅ sg-alb ($SG_ALB) — 80 public"

# sg-app: Sadece ALB'den uygulama trafiği ve Bastion'dan SSH
SG_APP=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-app" \
  --description "App Servers - ALB traffic only" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_APP" \
  --protocol tcp --port 3000 \
  --source-group "$SG_ALB" \
  --region "$AWS_REGION"

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_APP" \
  --protocol tcp --port 22 \
  --source-group "$SG_BASTION" \
  --region "$AWS_REGION"
echo "  ✅ sg-app ($SG_APP) — 3000 from ALB, 22 from Bastion"

# sg-rds: Sadece App sunucularından MySQL
SG_RDS=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-rds" \
  --description "RDS MySQL - App tier only, NO internet" \
  --vpc-id "$VPC_ID" \
  --region "$AWS_REGION" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_RDS" \
  --protocol tcp --port 3306 \
  --source-group "$SG_APP" \
  --region "$AWS_REGION"

# RDS'nin tüm outbound trafiğini engelle (egress kurallarını temizle)
aws ec2 revoke-security-group-egress \
  --group-id "$SG_RDS" \
  --protocol -1 --port -1 --cidr 0.0.0.0/0 --region "$AWS_REGION" 2>/dev/null || true
echo "  ✅ sg-rds ($SG_RDS) — 3306 from App only, NO outbound"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 3: RDS MySQL (Private, Encrypted, Multi-AZ)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "🗄️  [3/6] RDS MySQL Oluşturuluyor (Private + Encrypted)..."

# DB Subnet Group
aws rds create-db-subnet-group \
  --db-subnet-group-name "${PROJECT}-db-subnet-group" \
  --db-subnet-group-description "Private DB subnets for ${PROJECT}" \
  --subnet-ids "$SUBNET_DB_A" "$SUBNET_DB_B" \
  --region "$AWS_REGION"

# RDS Instance — Güvenli konfigürasyon (Deletion protection devre dışı bırakıldı ki sonradan silmek kolay olsun)
aws rds create-db-instance \
  --db-instance-identifier "${PROJECT}-db" \
  --db-instance-class db.t3.micro \
  --engine mysql \
  --engine-version "8.0" \
  --master-username admin \
  --master-user-password "$DB_ROOT_PASSWORD" \
  --db-name ecommerce_db \
  --db-subnet-group-name "${PROJECT}-db-subnet-group" \
  --vpc-security-group-ids "$SG_RDS" \
  --multi-az \
  --storage-encrypted \
  --storage-type gp3 \
  --allocated-storage 20 \
  --backup-retention-period 0 \
  --no-deletion-protection \
  --no-publicly-accessible \
  --region "$AWS_REGION"

echo "  ✅ RDS oluşturma başladı. Durumun 'available' olması bekleniyor (bu işlem yaklaşık 5-8 dakika sürer)..."
aws rds wait db-instance-available --db-instance-identifier "${PROJECT}-db" --region "$AWS_REGION"

DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "${PROJECT}-db" \
  --region "$AWS_REGION" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "  ✅ RDS veritabanı hazır. Endpoint: $DB_ENDPOINT"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 4: Dinamik UserData Scripti ve Launch Template
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "📝 [4/6] Dinamik UserData Hazırlanıyor ve Başlatma Şablonu Oluşturuluyor..."

# Dinamik UserData scripti oluştur
cat > aws/userdata-prod.sh <<EOF
#!/bin/bash
set -euo pipefail

# İşletim sistemi güncellemeleri ve Node.js 20 kurulumu
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs git

# Port yönlendirme (80 -> 3000)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 3000

APP_DIR="/app/ecommerce-secure"
mkdir -p "\$APP_DIR"
useradd -r -s /bin/false appuser
chown appuser:appuser "\$APP_DIR"

# Kodu klonla
git clone https://github.com/bernakalkann/SecureShop-Cloud.git "\$APP_DIR"

# Çevre değişkenleri (.env) dosyasını oluştur
cat > "\$APP_DIR/.env" <<EOT
NODE_ENV=production
PORT=3000
DB_HOST=$DB_ENDPOINT
DB_PORT=3306
DB_NAME=ecommerce_db
DB_USER=admin
DB_PASSWORD=$DB_ROOT_PASSWORD
SESSION_SECRET=$SESSION_SECRET
EOT

chown appuser:appuser "\$APP_DIR/.env"
chmod 600 "\$APP_DIR/.env"

# Bağımlılıkları kur
cd "\$APP_DIR"
sudo -u appuser npm ci --only=production

# Veritabanı tablolarını oluştur
sudo -u appuser DB_HOST=$DB_ENDPOINT DB_USER=admin DB_PASSWORD=$DB_ROOT_PASSWORD DB_NAME=ecommerce_db node initialize_db.js

# Systemd Servisi Oluştur
cat > /etc/systemd/system/ecommerce.service <<EOT
[Unit]
Description=Secure E-Commerce Node.js App
After=network.target

[Service]
Type=simple
User=appuser
WorkingDirectory=\$APP_DIR
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
EOF

# UserData scriptini base64'e dönüştür
USERDATA_BASE64=\$(base64 < aws/userdata-prod.sh | tr -d '\n')

# Launch Template oluştur
LAUNCH_TEMPLATE_ID=\$(aws ec2 create-launch-template \
  --launch-template-name "\${PROJECT}-lt" \
  --version-description "Secure E-Commerce App Server" \
  --region "\$AWS_REGION" \
  --launch-template-data "{
    \"ImageId\": \"\$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"\$SG_APP\"],
    \"UserData\": \"\$USERDATA_BASE64\",
    \"MetadataOptions\": {
      \"HttpTokens\": \"required\",
      \"HttpPutResponseHopLimit\": 1
    }
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)

echo "  ✅ Başlatma Şablonu (Launch Template) oluşturuldu: \$LAUNCH_TEMPLATE_ID"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 5: Application Load Balancer ve Auto Scaling Group
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "⚖️  [5/6] Load Balancer ve Auto Scaling Group Yapılandırılıyor..."

ALB_ARN=\$(aws elbv2 create-load-balancer \
  --name "\${PROJECT}-alb" \
  --subnets "\$SUBNET_PUBLIC" "\$SUBNET_PUBLIC_B" \
  --security-groups "\$SG_ALB" \
  --scheme internet-facing \
  --type application \
  --region "\$AWS_REGION" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Target Group (HTTP Port 3000)
TG_ARN=\$(aws elbv2 create-target-group \
  --name "\${PROJECT}-tg" \
  --protocol HTTP --port 3000 \
  --vpc-id "\$VPC_ID" \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --region "\$AWS_REGION" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# ALB HTTP Port 80 Listener (Doğrudan Target Group'a yönlendirir)
aws elbv2 create-listener \
  --load-balancer-arn "\$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn="\$TG_ARN" \
  --region "\$AWS_REGION"

# Auto Scaling Group oluştur (Private Subnets'e yerleştirilir)
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "\${PROJECT}-asg" \
  --launch-template "LaunchTemplateId=\${LAUNCH_TEMPLATE_ID},Version=\\\$Latest" \
  --min-size 2 --max-size 5 --desired-capacity 2 \
  --vpc-zone-identifier "\$SUBNET_APP" \
  --target-group-arns "\$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --region "\$AWS_REGION"

# ASG CPU %70 Politikasını uygula
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "\${PROJECT}-asg" \
  --policy-name "cpu-scale-out" \
  --policy-type TargetTrackingScaling \
  --region "\$AWS_REGION" \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"},
    "TargetValue": 70.0
  }'

echo "  ✅ ALB ve Auto Scaling Group (%70 CPU Tetikleyici) hazır."

# ─────────────────────────────────────────────────────────────────────────
# ADIM 6: CloudTrail (Audit Logging)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "📋 [6/6] CloudTrail Audit Logging Etkinleştiriliyor..."

TRAIL_BUCKET="\${PROJECT}-cloudtrail-logs-\$(date +%s)"
aws s3 mb "s3://\$TRAIL_BUCKET" --region "\$AWS_REGION"
aws s3api put-bucket-encryption \
  --bucket "\$TRAIL_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }' \
  --region "\$AWS_REGION"

aws cloudtrail create-trail \
  --name "\${PROJECT}-trail" \
  --s3-bucket-name "\$TRAIL_BUCKET" \
  --is-multi-region-trail \
  --enable-log-file-validation \
  --region "\$AWS_REGION"

aws cloudtrail start-logging --name "\${PROJECT}-trail" --region "\$AWS_REGION"
echo "  ✅ CloudTrail aktif — Tüm API çağrıları kayıt altında."

# ALB DNS adını al
ALB_DNS=\$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "\$ALB_ARN" \
  --region "\$AWS_REGION" \
  --query 'LoadBalancers[0].DNSName' --output text)

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║         KURULUM TAMAMLANDI ✅                 ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "👉 Uygulama Canlı URL'niz: http://\$ALB_DNS"
echo "👉 RDS Şifreniz: \$DB_ROOT_PASSWORD"
echo ""
echo "ℹ️  Sunucuların tamamen açılması ve veritabanı kurulumunun bitmesi"
echo "    yaklaşık 2-3 dakika sürebilir. Sonrasında yukarıdaki URL'den erişebilirsiniz!"
echo ""

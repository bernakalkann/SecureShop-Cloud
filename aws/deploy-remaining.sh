#!/bin/bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
PROJECT="ecommerce-secure"

echo "🔍 VPC ve alt ağ bilgileri AWS'den sorgulanıyor..."

# Query VPC ID
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${PROJECT}-vpc" \
  --region "$AWS_REGION" \
  --query "Vpcs[0].VpcId" --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
  echo "❌ Hata: ${PROJECT}-vpc bulunamadı!"
  exit 1
fi
echo "  ✅ VPC ID: $VPC_ID"

# Query Subnet IDs
SUBNET_PUBLIC=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT}-public-1a" \
  --region "$AWS_REGION" \
  --query "Subnets[0].SubnetId" --output text)

SUBNET_PUBLIC_B=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT}-public-1b" \
  --region "$AWS_REGION" \
  --query "Subnets[0].SubnetId" --output text)

SUBNET_APP=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=${PROJECT}-app-private-1a" \
  --region "$AWS_REGION" \
  --query "Subnets[0].SubnetId" --output text)

echo "  ✅ Public Subnet A: $SUBNET_PUBLIC"
echo "  ✅ Public Subnet B: $SUBNET_PUBLIC_B"
echo "  ✅ App Subnet: $SUBNET_APP"

# Query Security Groups
SG_APP=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=${PROJECT}-sg-app" \
  --region "$AWS_REGION" \
  --query "SecurityGroups[0].GroupId" --output text)

SG_ALB=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=${PROJECT}-sg-alb" \
  --region "$AWS_REGION" \
  --query "SecurityGroups[0].GroupId" --output text)

echo "  ✅ sg-app: $SG_APP"
echo "  ✅ sg-alb: $SG_ALB"

# Fetch RDS Endpoint
DB_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "${PROJECT}-db" \
  --region "$AWS_REGION" \
  --query 'DBInstances[0].Endpoint.Address' --output text)

if [ "$DB_ENDPOINT" == "None" ] || [ -z "$DB_ENDPOINT" ]; then
  echo "❌ Hata: RDS veritabanı adresi bulunamadı!"
  exit 1
fi
echo "  ✅ DB Endpoint: $DB_ENDPOINT"

# Secrets
DB_ROOT_PASSWORD="SecureEcomPass123!"
SESSION_SECRET="$(openssl rand -hex 32)"

# Find AMI
echo "🔍 En güncel Amazon Linux 2023 AMI adresi aranıyor..."
AMI_ID=$(aws ec2 describe-images \
  --region "$AWS_REGION" \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
  --query "Images[0].ImageId" \
  --output text)
echo "  ✅ AMI ID: $AMI_ID"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 4: Dinamik UserData Scripti ve Launch Template
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "📝 [4/6] Dinamik UserData Hazırlanıyor ve Başlatma Şablonu Oluşturuluyor..."

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

# Convert UserData to Base64
USERDATA_BASE64=$(base64 < aws/userdata-prod.sh | tr -d '\n')

# Create Launch Template
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name "${PROJECT}-lt" \
  --version-description "Secure E-Commerce App Server" \
  --region "$AWS_REGION" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"$SG_APP\"],
    \"UserData\": \"$USERDATA_BASE64\",
    \"MetadataOptions\": {
      \"HttpTokens\": \"required\",
      \"HttpPutResponseHopLimit\": 1
    }
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)

echo "  ✅ Başlatma Şablonu (Launch Template) oluşturuldu: $LAUNCH_TEMPLATE_ID"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 5: Application Load Balancer ve Auto Scaling Group
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "⚖️  [5/6] Load Balancer ve Auto Scaling Group Yapılandırılıyor..."

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${PROJECT}-alb" \
  --subnets "$SUBNET_PUBLIC" "$SUBNET_PUBLIC_B" \
  --security-groups "$SG_ALB" \
  --scheme internet-facing \
  --type application \
  --region "$AWS_REGION" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Target Group (HTTP Port 3000)
TG_ARN=$(aws elbv2 create-target-group \
  --name "${PROJECT}-tg" \
  --protocol HTTP --port 3000 \
  --vpc-id "$VPC_ID" \
  --health-check-path "/" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --region "$AWS_REGION" \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# ALB HTTP Port 80 Listener
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN" \
  --region "$AWS_REGION"

# Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${PROJECT}-asg" \
  --launch-template "LaunchTemplateId=${LAUNCH_TEMPLATE_ID},Version=\$Latest" \
  --min-size 2 --max-size 5 --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_APP" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --region "$AWS_REGION"

# ASG CPU %70 Policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "${PROJECT}-asg" \
  --policy-name "cpu-scale-out" \
  --policy-type TargetTrackingScaling \
  --region "$AWS_REGION" \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"},
    "TargetValue": 70.0
  }'

echo "  ✅ ALB ve Auto Scaling Group hazır."

# ─────────────────────────────────────────────────────────────────────────
# ADIM 6: CloudTrail (Audit Logging)
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "📋 [6/6] CloudTrail Audit Logging Etkinleştiriliyor..."

TRAIL_BUCKET="${PROJECT}-cloudtrail-logs-$(date +%s)"
aws s3 mb "s3://$TRAIL_BUCKET" --region "$AWS_REGION"
aws s3api put-bucket-encryption \
  --bucket "$TRAIL_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }' \
  --region "$AWS_REGION"

aws cloudtrail create-trail \
  --name "${PROJECT}-trail" \
  --s3-bucket-name "$TRAIL_BUCKET" \
  --is-multi-region-trail \
  --enable-log-file-validation \
  --region "$AWS_REGION"

aws cloudtrail start-logging --name "${PROJECT}-trail" --region "$AWS_REGION"
echo "  ✅ CloudTrail aktif."

# ALB DNS
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --region "$AWS_REGION" \
  --query 'LoadBalancers[0].DNSName' --output text)

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║         KURULUM TAMAMLANDI ✅                 ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "👉 Uygulama Canlı URL'niz: http://$ALB_DNS"
echo "👉 RDS Şifreniz: $DB_ROOT_PASSWORD"
echo ""

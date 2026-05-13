#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# setup-aws.sh — AWS Altyapı Kurulum Scripti
# Proje 4: Güvenli E-Ticaret Altyapısı (Defense in Depth)
#
# KULLANIM:
#   chmod +x setup-aws.sh
#   export AWS_REGION=us-east-1
#   ./setup-aws.sh
#
# ÖNKOŞULlar:
#   - AWS CLI kurulu ve yapılandırılmış (aws configure)
#   - IAM yetkileri: VPC, EC2, RDS, ELB, WAF Full Access
# ═══════════════════════════════════════════════════════════════════════════

set -euo pipefail  # Hata durumunda dur

AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT="ecommerce-secure"
ADMIN_IP=$(curl -s https://api.ipify.org)/32  # Mevcut IP'yi otomatik al

echo "╔══════════════════════════════════════════════╗"
echo "║   AWS Güvenli E-Ticaret Altyapı Kurulumu    ║"
echo "╚══════════════════════════════════════════════╝"
echo "Region: $AWS_REGION | Admin IP: $ADMIN_IP"
echo ""

# ─────────────────────────────────────────────────────────────────────────
# ADIM 1: VPC ve Subnets
# ─────────────────────────────────────────────────────────────────────────
echo "📦 [1/6] VPC ve Subnet Oluşturuluyor..."

VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region "$AWS_REGION" \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames
aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="${PROJECT}-vpc"
echo "  ✅ VPC: $VPC_ID"

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$AWS_REGION" \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
echo "  ✅ Internet Gateway: $IGW_ID"

# Public Subnet (ALB için) — AZ-a
SUBNET_PUBLIC=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$SUBNET_PUBLIC" --tags Key=Name,Value="${PROJECT}-public-1a"

# Public Subnet — AZ-b (ALB en az 2 AZ gerektirir)
SUBNET_PUBLIC_B=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.4.0/24 \
  --availability-zone "${AWS_REGION}b" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$SUBNET_PUBLIC_B" --tags Key=Name,Value="${PROJECT}-public-1b"

# Private Subnet — App Tier (AZ-a)
SUBNET_APP=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' --output text)
aws ec2 create-tags --resources "$SUBNET_APP" --tags Key=Name,Value="${PROJECT}-app-private-1a"

# Private Subnet — DB Tier (AZ-a ve AZ-b, Multi-AZ için)
SUBNET_DB_A=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.3.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --query 'Subnet.SubnetId' --output text)

SUBNET_DB_B=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.5.0/24 \
  --availability-zone "${AWS_REGION}b" \
  --query 'Subnet.SubnetId' --output text)

aws ec2 create-tags --resources "$SUBNET_DB_A" --tags Key=Name,Value="${PROJECT}-db-private-1a"
aws ec2 create-tags --resources "$SUBNET_DB_B" --tags Key=Name,Value="${PROJECT}-db-private-1b"

echo "  ✅ Subnets oluşturuldu (Public/App/DB)"

# Route Table — Public
RT_PUBLIC=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RT_PUBLIC" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW_ID"
aws ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC"
aws ec2 associate-route-table --route-table-id "$RT_PUBLIC" --subnet-id "$SUBNET_PUBLIC_B"

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
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_BASTION" \
  --protocol tcp --port 22 \
  --cidr "$ADMIN_IP"  # Sadece admin IP
echo "  ✅ sg-bastion ($SG_BASTION) — SSH: $ADMIN_IP only"

# sg-alb: İnternet'ten 80/443
SG_ALB=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-alb" \
  --description "ALB - Public HTTP/HTTPS" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ALB" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ALB" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0   # HTTP→HTTPS redirect için
echo "  ✅ sg-alb ($SG_ALB) — 80/443 public"

# sg-app: Sadece ALB'den uygulama trafiği
SG_APP=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-app" \
  --description "App Servers - ALB traffic only" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_APP" \
  --protocol tcp --port 3000 \
  --source-group "$SG_ALB"  # Sadece ALB'den gelen trafik

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_APP" \
  --protocol tcp --port 22 \
  --source-group "$SG_BASTION"  # SSH sadece Bastion'dan
echo "  ✅ sg-app ($SG_APP) — 3000 from ALB, 22 from Bastion"

# sg-rds: Sadece App sunucularından MySQL
SG_RDS=$(aws ec2 create-security-group \
  --group-name "${PROJECT}-sg-rds" \
  --description "RDS MySQL - App tier only, NO internet" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_RDS" \
  --protocol tcp --port 3306 \
  --source-group "$SG_APP"  # SADECE uygulama sunucularından

# RDS'nin tüm outbound trafiğini engelle
aws ec2 revoke-security-group-egress \
  --group-id "$SG_RDS" \
  --protocol -1 --port -1 --cidr 0.0.0.0/0 2>/dev/null || true
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
  --subnet-ids "$SUBNET_DB_A" "$SUBNET_DB_B"

# RDS Instance — Güvenli konfigürasyon
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
  --multi-az \                       # Availability: Otomatik failover
  --storage-encrypted \              # Confidentiality: AES-256 at-rest
  --storage-type gp3 \
  --allocated-storage 20 \
  --backup-retention-period 7 \      # 7 günlük otomatik backup
  --preferred-backup-window "03:00-04:00" \
  --deletion-protection \            # Kazara silme koruması
  --no-publicly-accessible           # İnternete KAPALI (kritik!)

echo "  ✅ RDS oluşturma başladı (5-10 dakika sürer)"
echo "  ✅ Özellikler: Multi-AZ, Encrypted, Private, Deletion Protection ON"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 4: Application Load Balancer
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "⚖️  [4/6] Application Load Balancer Yapılandırılıyor..."

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name "${PROJECT}-alb" \
  --subnets "$SUBNET_PUBLIC" "$SUBNET_PUBLIC_B" \
  --security-groups "$SG_ALB" \
  --scheme internet-facing \
  --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Target Group
TG_ARN=$(aws elbv2 create-target-group \
  --name "${PROJECT}-tg" \
  --protocol HTTP --port 3000 \
  --vpc-id "$VPC_ID" \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# HTTP → HTTPS Redirect (301)
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP --port 80 \
  --default-actions Type=redirect,RedirectConfig="{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}"

echo "  ✅ ALB: $ALB_ARN"
echo "  ✅ HTTP→HTTPS 301 redirect aktif"
echo "  ℹ️  HTTPS listener için ACM sertifikası eklenmeli"

# ─────────────────────────────────────────────────────────────────────────
# ADIM 5: Auto Scaling Group
# ─────────────────────────────────────────────────────────────────────────
echo ""
echo "📈 [5/6] Auto Scaling Group Yapılandırılıyor..."

# Launch Template
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name "${PROJECT}-lt" \
  --version-description "Secure E-Commerce App Server" \
  --launch-template-data "{
    \"ImageId\": \"ami-0c02fb55956c7d316\",
    \"InstanceType\": \"t3.micro\",
    \"SecurityGroupIds\": [\"$SG_APP\"],
    \"UserData\": \"$(base64 -i aws/userdata.sh)\",
    \"MetadataOptions\": {
      \"HttpTokens\": \"required\",
      \"HttpPutResponseHopLimit\": 1
    }
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' --output text)

# Auto Scaling Group
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name "${PROJECT}-asg" \
  --launch-template "LaunchTemplateId=${LAUNCH_TEMPLATE_ID},Version=\$Latest" \
  --min-size 2 --max-size 6 --desired-capacity 2 \
  --vpc-zone-identifier "$SUBNET_APP" \
  --target-group-arns "$TG_ARN" \
  --health-check-type ELB \
  --health-check-grace-period 300

# CPU %70'i geçince scale-out
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name "${PROJECT}-asg" \
  --policy-name "cpu-scale-out" \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {"PredefinedMetricType": "ASGAverageCPUUtilization"},
    "TargetValue": 70.0
  }'

echo "  ✅ ASG: min=2, max=6, CPU target=70%"

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
  }'

aws cloudtrail create-trail \
  --name "${PROJECT}-trail" \
  --s3-bucket-name "$TRAIL_BUCKET" \
  --is-multi-region-trail \
  --enable-log-file-validation

aws cloudtrail start-logging --name "${PROJECT}-trail"
echo "  ✅ CloudTrail aktif — Tüm API çağrıları kayıt altında"

echo ""
echo "╔═══════════════════════════════════════════════╗"
echo "║         KURULUM TAMAMLANDI ✅                 ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "Sonraki Adımlar:"
echo "  1. ACM'den SSL sertifikası al ve ALB HTTPS listener'a ekle"
echo "  2. WAF WebACL oluştur ve ALB'ye bağla (setup-waf.sh)"
echo "  3. RDS oluşturulduktan sonra schema.sql'i yükle"
echo "  4. AWS WAF → Rate limiting aktif et"

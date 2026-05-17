# 🔒 SecureShop — AWS Güvenli E-Ticaret Altyapısı

> **Bulut Bilişim Dersi — Proje 4**  
> Security-by-Design | DevSecOps | OWASP Top 10 | AWS Defense in Depth

---

## 📋 Proje Özeti

Bu proje, AWS bulut platformu üzerinde **Derinlemesine Savunma (Defense in Depth)** ilkesiyle inşa edilmiş, ölçeklenebilir ve güvenli bir e-ticaret altyapısını kapsamaktadır. Yapay zeka bir **kopyala-yapıştır aracı** olarak değil, **Siber Güvenlik Denetçisi (Security Auditor)** rolünde kullanılmıştır.

---

## 🏗️ Mimari

```
Internet
    │
[AWS WAF] ── Rate Limiting, SQLi/XSS imzaları
    │
[ALB] ── TLS 1.2+, HTTP→HTTPS 301 Redirect
    │
[EC2 Auto Scaling Group] ── Private Subnet
│   Node.js + Helmet + CSRF + Rate Limiting
    │
[RDS MySQL] ── Private Subnet, Multi-AZ, KMS Encrypted
```

---

## 🛡️ Güvenlik Kontrolleri (OWASP Top 10)

| OWASP ID | Zafiyet | Uygulanan Önlem |
|---|---|---|
| A01:2021 | Broken Access Control | RBAC + IDOR koruması + session ownership |
| A02:2021 | Cryptographic Failures | TLS 1.2+, bcrypt, KMS AES-256 |
| A03:2021 | Injection (SQLi/XSS) | Parameterized queries + express-validator + helmet CSP |
| A05:2021 | Security Misconfiguration | Helmet.js, verbose error gizleme |
| A07:2021 | Auth Failures | bcrypt saltRounds=12, rate limiting, session fixation koruması |
| A09:2021 | Logging & Monitoring | Winston logger, CloudTrail, security audit log |

---

## 📁 Proje Yapısı

```
ecommerce-secure/
├── src/
│   ├── app.js                 # Ana uygulama (7 güvenlik katmanı)
│   ├── routes/
│   │   ├── auth.js            # Login/Register (bcrypt + rate limit)
│   │   ├── products.js        # Ürünler (RBAC + parameterized)
│   │   └── checkout.js        # Sipariş (transaction + IDOR koruması)
│   ├── middleware/
│   │   ├── rateLimiter.js     # Brute force koruması
│   │   ├── validation.js      # Input validation (SQLi/XSS)
│   │   └── errorHandler.js    # Güvenli hata yönetimi
│   ├── models/
│   │   └── db.js              # MySQL connection pool (SSL)
│   └── utils/
│       └── logger.js          # Winston security logger
├── public/
│   └── index.html             # Frontend UI
├── aws/
│   ├── setup-aws.sh           # Tam altyapı kurulum scripti
│   ├── schema.sql             # Veritabanı şeması
│   └── userdata.sh            # EC2 bootstrap (SSM secrets)
├── .env.example               # Ortam değişkeni şablonu
├── .gitignore                 # Secrets dışlama kuralları
└── package.json
```

---

## 🚀 Kurulum

### Yerel Geliştirme

```bash
# 1. Repoyu klonla
git clone https://github.com/KULLANICI_ADIN/ecommerce-secure.git
cd ecommerce-secure

# 2. Bağımlılıkları yükle
npm install

# 3. Environment değişkenlerini ayarla
cp .env.example .env
# .env dosyasını düzenle (DB bilgileri)

# 4. Veritabanını oluştur (MySQL kurulu olmalı)
mysql -u root -p < aws/schema.sql

# 5. Uygulamayı başlat
npm run dev
```

### AWS Deployment

```bash
# AWS CLI yapılandır
aws configure

# DB şifresini ortam değişkeni olarak ver
export DB_ROOT_PASSWORD="GuclüŞifre@123!"
export AWS_REGION="us-east-1"

# Altyapıyı kur (VPC, SG, RDS, ALB, ASG, CloudTrail)
chmod +x aws/setup-aws.sh
./aws/setup-aws.sh
```

---

## 🔐 CIA Triad Uygulaması

### Gizlilik (Confidentiality)
- RDS → Private Subnet (internete sıfır erişim)
- TLS 1.2+ ile aktarım şifrelemesi
- AWS KMS ile durağan şifreleme (AES-256)
- Secrets → AWS SSM Parameter Store (hardcoded credential yok)

### Bütünlük (Integrity)
- Parameterized queries (SQL Injection koruması)
- DB transaction (atomik sipariş işlemi)
- CloudTrail (tüm API değişiklikleri kayıt altında)
- Input validation (sunucu tarafında)

### Erişilebilirlik (Availability)
- RDS Multi-AZ (otomatik failover ~120s)
- Auto Scaling (CPU %70 → scale-out)
- AWS WAF Rate Limiting (2000 req/5dk/IP)
- ALB Health Check (sağlıksız instance devre dışı)

---

## 📦 Bağımlılıklar

```bash
npm install helmet express-validator csurf express-rate-limit \
            bcryptjs dotenv winston express-session mysql2 cors
```

---

## 🔍 Güvenlik Test Komutları

```bash
# SQL Injection testi (WAF tarafından engellenmeli)
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin'\'' OR 1=1--","password":"test"}'
# Beklenen: 400 Validation Error (string escaped)

# Brute Force testi (Rate Limiting devreye girmeli)
for i in {1..6}; do
  curl -X POST http://localhost:3000/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"test","password":"wrong"}'
done
# 6. istekte beklenen: 429 Too Many Requests

# CSRF testi (token olmadan POST)
curl -X POST http://localhost:3000/api/checkout \
  -H "Content-Type: application/json" \
  -d '{"items":[]}'
# Beklenen: 403 CSRF_INVALID
```

---

## 📊 Tehdit Modeli

| Saldırı | Vektör | Kontrol | Durum |
|---|---|---|---|
| SQL Injection | Login, Arama | Parameterized Query | ✅ Engellendi |
| XSS | Ürün arama, yorum | CSP + escape | ✅ Engellendi |
| CSRF | Sipariş, ödeme | Synchronizer Token | ✅ Engellendi |
| Brute Force | Login | Rate Limit 5/15dk | ✅ Engellendi |
| Session Hijacking | Cookie | httpOnly + Secure | ✅ Engellendi |
| IDOR | Sipariş detayı | user_id ownership check | ✅ Engellendi |
| DDoS | ALB | WAF + Auto Scaling | ✅ Azaltıldı |

---

## 📝 Referanslar

- [OWASP Top 10 (2021)](https://owasp.org/Top10/)
- [AWS Well-Architected Framework — Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [CIS AWS Foundations Benchmark v1.5](https://www.cisecurity.org/benchmark/amazon_web_services)
- [NIST SP 800-30 Risk Assessment Guide](https://csrc.nist.gov/publications/detail/sp/800-30/rev-1/final)
- [Node.js Security Best Practices](https://nodejs.org/en/docs/guides/security/)

---

*Proje 4 | Bulut Bilişim Dersi | Security-by-Design*

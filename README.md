# 🔒 SecureShop — Bulut Tabanlı ve Güvenli E-Ticaret Platformu (DevSecOps)

Yüksek kullanılabilirlik, otomatik ölçeklendirme ve derinlemesine bulut savunması (Defense in Depth) ile OWASP Top 10 uygulama güvenliği standartlarını tek bir çatı altında birleştiren, endüstri standardı bir **DevSecOps** e-ticaret platformudur.

---

## 📋 Proje Özeti

SecureShop, modern bulut (Cloud-Native) mimarilerini ve siber güvenlik en iyi uygulamalarını (Best Practices) sergilemek amacıyla tasarlanmış ölçeklenebilir ve yüksek güvenlikli bir e-ticaret platformudur. Proje; hem **akıllı bulut altyapısı tasarımı** (Elasticity, Load Balancing, VPC Ağ Yönetimi) hem de **katı uygulama güvenliği standartları** (Girdi doğrulama, oturum yönetimi, veri şifreleme) temel alınarak kurumsal mimari standartlarında inşa edilmiştir.

---

## 🏗️ 1. Bulut Altyapısı ve Ölçeklenebilirlik (Cloud Infrastructure & Elasticity)

Uygulamanın bulut mimarisi, kesintisiz hizmet (High Availability) ve dinamik ölçeklenebilirlik prensipleriyle tasarlanmıştır.

```
                  [ 🌐 Kullanıcı Trafiği ]
                            │
              [ AWS WAF - Güvenlik Duvarı ]
                            │
      [ ALB - Application Load Balancer (Public Subnet) ]
                            │
     ┌──────────────────────┴──────────────────────┐
     ▼                                             ▼
[ EC2 Sunucu 1 (AZ1) ]                        [ EC2 Sunucu 2 (AZ2) ]
Private Subnet                                Private Subnet
Auto Scaling Grubu                            Auto Scaling Grubu
     │                                             │
     └──────────────────────┬──────────────────────┘
                            ▼
              [ RDS MySQL (Private Subnet) ]
                     Multi-AZ Replikasyon
```

### ⚙️ Bulut Mimarisi Özellikleri:
* **Yüksek Kullanılabilirlik (High Availability):** Sistem, Multi-AZ (Farklı kullanılabilirlik bölgeleri) yapısında çalışır. Herhangi bir veri merkezinde kesinti yaşandığında trafik diğer bölgeye otomatik yönlendirilir.
* **Otomatik Ölçeklendirme (Auto Scaling Group - ASG):** İşlemci (CPU) yükü %70 barajını aştığında, sistem otomatik olarak yeni EC2 sunucu örneklerini devreye alır. Trafik azaldığında maliyeti korumak için sunucuları otomatik kapatır.
* **Yük Dengeleme (Application Load Balancer):** Gelen kullanıcı trafiğini arka plandaki sağlıklı sunuculara dengeli şekilde dağıtır ve sunucuların sağlık durumlarını (Health Checks) anlık izler.
* **İzole Ağ Tasarımı (VPC & Subnets):** Uygulama sunucuları ve RDS veritabanı doğrudan internet erişimi olmayan **Private Subnet**'lerde (Özel Ağ) çalıştırılır. Dış dünya sunuculara doğrudan erişemez.

---

## 🛡️ 2. Uygulama Güvenliği Mimarisi (Application Security & OWASP Top 10)

Uygulama, tasarım aşamasından itibaren güvenlik odaklı (Security-by-Design) olarak kodlanmış ve OWASP Top 10 standartlarına göre sertleştirilmiştir.

| OWASP ID | Güvenlik Zafiyeti | SecureShop Tarafından Uygulanan Önlem |
|---|---|---|
| **A01:2021** | Kırık Erişim Kontrolü (Broken Access Control) | Kullanıcı kimliği doğrulaması, IDOR (güvenli olmayan nesne referansı) koruması ve sipariş sahipliği kontrolleri. |
| **A02:2021** | Kriptografik Hatalar (Cryptographic Failures) | Hassas verilerin aktarımı sırasında şifreleme ve şifrelerin **bcrypt (12 Salt Rounds)** algoritmalarıyla tek yönlü hashlenmesi. |
| **A03:2021** | Enjeksiyon (SQLi / XSS) | Tamamen parametrik veritabanı sorguları (`db.execute`) ile SQLi engelleme ve `express-validator` filtrelemesi ile XSS koruması. |
| **A05:2021** | Güvenlik Yapılandırma Hatası | `Helmet.js` ile gereksiz başlıkların gizlenmesi ve tarayıcıya katı güvenlik direktifleri (CSP/HSTS) gönderilmesi. |
| **A07:2021** | Kimlik Doğrulama Hataları | Brute-force saldırılarına karşı IP bazlı **Rate Limiting** ve oturum çalınmasını engelleyen `Session ID` yenilemesi. |
| **A09:2021** | Güvenlik Günlüğü (Logging) | `Winston` kütüphanesiyle IP adresi, istek metotları ve kullanıcı detaylarını içeren güvenlik denetim günlükleri (Audit Logs). |

---

## 📁 Proje Klasör Yapısı

```
ecommerce-secure/
├── src/
│   ├── app.js                 # Ana Express uygulaması (Güvenlik katmanları)
│   ├── routes/
│   │   ├── auth.js            # Kimlik doğrulama işlemleri (Kayıt/Giriş)
│   │   ├── products.js        # Ürün yönetimi ve filtreleme
│   │   └── checkout.js        # Güvenli sipariş ve ödeme işlemleri
│   ├── middleware/
│   │   ├── rateLimiter.js     # Brute force / DDoS koruma filtreleri
│   │   ├── validation.js      # Girdi doğrulama ve XSS filtreleme
│   │   └── errorHandler.js    # Sistem bilgilerini gizleyen güvenli hata yönetimi
│   ├── models/
│   │   └── db.js              # Veritabanı bağlantı havuzu yönetimi
│   └── utils/
│       └── logger.js          # Winston tabanlı güvenlik denetim günlüğü
├── public/
│   └── index.html             # Şık, modern ve güvenli ön yüz
├── aws/
│   ├── schema.sql             # Veritabanı şeması ve kısıtlar (constraints)
│   └── setup-aws.sh           # AWS altyapı dağıtım scripti
├── .env.example               # Örnek çevre değişkenleri
├── README.md                  # Proje ana belgesi
└── package.json               # Bağımlılık yönetimi
```

---

## 🚀 Kurulum ve Çalıştırma

### 💻 Yerel Geliştirme (Local Development)

1. Projeyi bilgisayarınıza klonlayın veya indirin:
   ```bash
   git clone https://github.com/bernakalkann/ecommerce-secure.git
   cd ecommerce-secure
   ```

2. Gerekli kütüphaneleri yükleyin:
   ```bash
   npm install
   ```

3. Çevre değişkenlerini ayarlayın:
   * `.env.example` dosyasının adını `.env` olarak değiştirin ve veritabanı bağlantı bilgilerinizi girin.

4. Veritabanı şemasını yerel MySQL sunucunuzda çalıştırın:
   ```bash
   mysql -u root -p < aws/schema.sql
   ```

5. Uygulamayı başlatın:
   ```bash
   npm start
   ```

---

## 🔍 Güvenlik Denetim ve Test Komutları

Uygulamanın siber güvenlik katmanlarını test etmek için aşağıdaki komutları kullanabilirsiniz:

* **SQL Injection Testi (Engellenmelidir):**
  ```bash
  curl -X POST http://localhost:3000/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin'\'' OR 1=1--","password":"test"}'
  # Sonuç: 400 Validation Error (Girdi filtrelenerek SQL enjeksiyonu önlenir).
  ```

* **Brute Force / DDoS Testi (Rate Limiter Devreye Girmelidir):**
  ```bash
  for i in {1..6}; do
    curl -X POST http://localhost:3000/api/auth/login \
      -H "Content-Type: application/json" \
      -d '{"username":"test","password":"wrong"}'
  done
  # Sonuç: 6. denemeden sonra "429 Too Many Requests" engeli devreye girer.
  ```

* **CSRF Saldırı Testi (Token Olmadan POST İstekleri Engellenmelidir):**
  ```bash
  curl -X POST http://localhost:3000/api/checkout \
    -H "Content-Type: application/json" \
    -d '{"items":[]}'
  # Sonuç: 403 CSRF_INVALID veya kimlik doğrulama hatası alınır.
  ```

---

## 📊 Güvenlik Tehdit Modeli ve Çözümler (Threat Modeling)

| Tehdit | Saldırı Vektörü | Alınan Önlem / Kontrol | Sonuç |
|---|---|---|---|
| **SQL Injection** | Girdi Alanları | Parameterized Queries (Parametrik Sorgu) | ✅ Engellendi |
| **Cross-Site Scripting (XSS)** | Ürün arama / Yorumlar | CSP Başlığı + HTML Entity Escaping | ✅ Engellendi |
| **CSRF (İstek Sahteciliği)** | Sipariş / checkout | Synchronizer Token Pattern | ✅ Engellendi |
| **Brute Force (Kaba Kuvvet)** | Giriş Paneli | Rate Limiter (Zaman & İstek Sınırı) | ✅ Engellendi |
| **Session Hijacking** | Çerez Çalma | HttpOnly + Secure + SameSite Çerezleri | ✅ Engellendi |
| **DDoS (Hizmet Engelleme)** | Genel Trafik | AWS WAF + Auto Scaling + Rate Limiter | ✅ Risk En Aza İndirildi |

---

## 📝 Referanslar ve Kaynakça

* **OWASP Foundation:** [OWASP Top 10 Web Application Security Risks (2021)](https://owasp.org/Top10/)
* **Amazon Web Services:** [AWS Well-Architected Framework - Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
* **NIST (National Institute of Standards and Technology):** [SP 800-30 Guide for Conducting Risk Assessments](https://csrc.nist.gov/publications/detail/sp/800-30/rev-1/final)
* **CIS (Center for Internet Security):** [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services)

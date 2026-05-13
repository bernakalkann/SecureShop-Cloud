-- ═══════════════════════════════════════════════════════════
-- schema.sql — E-Ticaret Veritabanı Şeması (MySQL 8.0)
-- Güvenlik: En az yetki, şifrelenmiş alanlar, audit columns
-- ═══════════════════════════════════════════════════════════

CREATE DATABASE IF NOT EXISTS ecommerce_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE ecommerce_db;

-- ─── Kullanıcılar ────────────────────────────────────────
CREATE TABLE users (
  id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  username        VARCHAR(50) NOT NULL UNIQUE,
  email           VARCHAR(255) NOT NULL UNIQUE,
  password_hash   VARCHAR(255) NOT NULL,     -- bcrypt hash (plain password ASLA saklanmaz)
  role            ENUM('customer','admin') NOT NULL DEFAULT 'customer',
  is_active       TINYINT(1) NOT NULL DEFAULT 1,
  failed_logins   INT UNSIGNED DEFAULT 0,    -- Brute force izleme
  locked_until    DATETIME NULL,
  last_login_at   DATETIME NULL,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_username (username),
  INDEX idx_email (email)
) ENGINE=InnoDB;

-- ─── Kategoriler ─────────────────────────────────────────
CREATE TABLE categories (
  id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name      VARCHAR(100) NOT NULL,
  slug      VARCHAR(100) NOT NULL UNIQUE,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ─── Ürünler ─────────────────────────────────────────────
CREATE TABLE products (
  id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  name          VARCHAR(255) NOT NULL,
  description   TEXT,
  price         DECIMAL(10,2) NOT NULL,
  stock         INT UNSIGNED NOT NULL DEFAULT 0,
  image_url     VARCHAR(500),
  category_id   INT UNSIGNED,
  is_active     TINYINT(1) NOT NULL DEFAULT 1,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
  INDEX idx_category (category_id),
  FULLTEXT INDEX idx_search (name, description)
) ENGINE=InnoDB;

-- ─── Siparişler ──────────────────────────────────────────
CREATE TABLE orders (
  id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  user_id           INT UNSIGNED NOT NULL,
  total_amount      DECIMAL(10,2) NOT NULL,
  shipping_address  JSON NOT NULL,           -- Yapılandırılmış adres
  status            ENUM('pending','confirmed','shipped','delivered','cancelled') DEFAULT 'pending',
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE RESTRICT,
  INDEX idx_user_orders (user_id),
  INDEX idx_status (status)
) ENGINE=InnoDB;

-- ─── Sipariş Kalemleri ────────────────────────────────────
CREATE TABLE order_items (
  id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  order_id    INT UNSIGNED NOT NULL,
  product_id  INT UNSIGNED NOT NULL,
  quantity    INT UNSIGNED NOT NULL,
  unit_price  DECIMAL(10,2) NOT NULL,        -- O anki fiyat saklanır (değişime karşı)
  FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT,
  INDEX idx_order (order_id)
) ENGINE=InnoDB;

-- ─── Güvenlik Audit Log ──────────────────────────────────
CREATE TABLE security_audit_log (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  event_type  VARCHAR(100) NOT NULL,
  user_id     INT UNSIGNED NULL,
  ip_address  VARCHAR(45) NOT NULL,
  user_agent  VARCHAR(500),
  details     JSON,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_event_type (event_type),
  INDEX idx_created_at (created_at),
  INDEX idx_ip (ip_address)
) ENGINE=InnoDB;

-- ─── En Az Yetki İlkesi: Uygulama DB Kullanıcısı ─────────
-- NOT: Bu komutları AWS RDS'de root ile çalıştır
-- CREATE USER 'app_user'@'%' IDENTIFIED BY 'STRONG_PASSWORD';
-- GRANT SELECT, INSERT, UPDATE ON ecommerce_db.* TO 'app_user'@'%';
-- GRANT DELETE ON ecommerce_db.order_items TO 'app_user'@'%';
-- REVOKE DROP, CREATE, ALTER, INDEX ON ecommerce_db.* FROM 'app_user'@'%';
-- FLUSH PRIVILEGES;

-- ─── Örnek Veriler ───────────────────────────────────────
INSERT INTO categories (name, slug) VALUES
  ('Electronics', 'electronics'),
  ('Clothing', 'clothing'),
  ('Books', 'books');

INSERT INTO products (name, description, price, stock, category_id) VALUES
  ('Laptop Pro 15', 'High-performance laptop for professionals', 1299.99, 50, 1),
  ('Wireless Headphones', 'Noise-cancelling over-ear headphones', 199.99, 120, 1),
  ('Python Programming Book', 'Complete guide to Python development', 39.99, 200, 3),
  ('Secure Coding T-Shirt', '100% cotton developer tee', 24.99, 75, 2);

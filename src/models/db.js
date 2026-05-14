/**
 * db.js — Güvenli MySQL Bağlantı Havuzu
 *
 * Güvenlik Notları:
 * - Bağlantı bilgileri .env'den okunur (hardcoded credential YOK)
 * - Connection pool kullanılır (kaynak tüketimi saldırılarına karşı)
 * - Tüm sorgular parameterized query ile çalışır (SQL Injection koruması)
 */
const mysql = require('mysql2/promise');
const logger = require('../utils/logger');

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT, 10) || 3306,
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,

  // Bağlantı havuzu limitleri (DoS koruması)
  connectionLimit: 10,
  queueLimit: 50,
  waitForConnections: true,
  connectTimeout: 10000,

  // SSL/TLS (Production RDS bağlantısı için)
  ssl: process.env.NODE_ENV === 'production'
    ? { rejectUnauthorized: true }
    : false,
});

// Bağlantı testi
pool.getConnection()
  .then((conn) => {
    logger.info('Database connection pool initialized successfully');
    conn.release();
  })
  .catch((err) => {
    logger.error('Database connection failed', { error: err.message });
    process.exit(1); // Bağlantı yoksa uygulamayı başlatma
  });

module.exports = pool;

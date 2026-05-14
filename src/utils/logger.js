/**
 * logger.js — Merkezi Winston Logger
 * Güvenlik olaylarını yapılandırılmış formatta kaydeder.
 * Hassas veri (şifre, token) log'a yazılmaz.
 */
const winston = require('winston');
const path = require('path');

const { combine, timestamp, json, colorize, simple } = winston.format;

// Log dizini
const logDir = path.join(__dirname, '../../logs');

const logger = winston.createLogger({
  level: process.env.NODE_ENV === 'production' ? 'warn' : 'debug',
  format: combine(timestamp(), json()),
  defaultMeta: { service: 'ecommerce-secure' },
  transports: [
    // Genel log dosyası
    new winston.transports.File({
      filename: path.join(logDir, 'app.log'),
      maxsize: 5242880, // 5MB
      maxFiles: 5,
    }),
    // Sadece hata logları
    new winston.transports.File({
      filename: path.join(logDir, 'error.log'),
      level: 'error',
      maxsize: 5242880,
      maxFiles: 5,
    }),
  ],
});

// Development ortamında konsola da yaz
if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: combine(colorize(), simple()),
  }));
}

/**
 * Güvenlik olayını logla (başarısız login, rate limit, CSRF ihlali vb.)
 * @param {string} event - Olay tipi
 * @param {Object} meta - Ek metadata (ip, userId vb.)
 */
logger.security = (event, meta = {}) => {
  // Hassas alanları temizle
  const sanitized = { ...meta };
  delete sanitized.password;
  delete sanitized.token;
  delete sanitized.secret;

  logger.warn({ event: `SECURITY::${event}`, ...sanitized });
};

module.exports = logger;

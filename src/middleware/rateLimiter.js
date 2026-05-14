/**
 * rateLimiter.js — Endpoint Bazlı Rate Limiting Middleware
 *
 * Güvenlik Amacı:
 * - Brute Force saldırılarını engeller (OWASP A07:2021)
 * - CIA Triad - Availability: aşırı yük altında hizmetin çökmesini önler
 */
const rateLimit = require('express-rate-limit');
const logger = require('../utils/logger');

// Ortak rate limit handler
const onLimitReached = (req, res, options) => {
  logger.security('RATE_LIMIT_EXCEEDED', {
    ip: req.ip,
    path: req.path,
    method: req.method,
    userAgent: req.get('User-Agent'),
  });
};

/**
 * Login endpoint limiti: 5 başarısız deneme / 15 dakika
 * OWASP A07:2021 - Brute Force koruması
 */
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 dakika
  max: 5,
  message: {
    error: 'Too many login attempts. Please try again in 15 minutes.',
    code: 'RATE_LIMIT_EXCEEDED',
  },
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true, // Başarılı girişler sayılmaz
  handler: (req, res, next, options) => {
    onLimitReached(req, res, options);
    res.status(429).json(options.message);
  },
});

/**
 * Register endpoint limiti: 3 hesap / saat
 */
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 saat
  max: 3,
  message: {
    error: 'Too many accounts created. Please try again in an hour.',
    code: 'RATE_LIMIT_EXCEEDED',
  },
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res, next, options) => {
    onLimitReached(req, res, options);
    res.status(429).json(options.message);
  },
});

/**
 * Genel API limiti: 100 istek / 15 dakika
 */
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: {
    error: 'Too many requests. Please slow down.',
    code: 'RATE_LIMIT_EXCEEDED',
  },
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res, next, options) => {
    onLimitReached(req, res, options);
    res.status(429).json(options.message);
  },
});

module.exports = { loginLimiter, registerLimiter, apiLimiter };

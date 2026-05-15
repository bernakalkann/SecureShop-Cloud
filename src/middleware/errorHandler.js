/**
 * errorHandler.js — Merkezi Hata Yönetimi
 *
 * Güvenlik Amacı:
 * - Stack trace ve iç hata detaylarını kullanıcıya GÖSTERMEZ
 * - OWASP A05:2021 - Security Misconfiguration: verbose error önleme
 * - Tüm hatalar güvenli biçimde loglanır
 */
const logger = require('../utils/logger');

/**
 * 404 Handler
 */
const notFoundHandler = (req, res) => {
  logger.debug('404 Not Found', { path: req.path, method: req.method, ip: req.ip });
  res.status(404).json({ error: 'Resource not found' });
};

/**
 * CSRF Hata Handler
 */
const csrfErrorHandler = (err, req, res, next) => {
  if (err.code === 'EBADCSRFTOKEN') {
    logger.security('CSRF_TOKEN_INVALID', {
      ip: req.ip,
      path: req.path,
      method: req.method,
      userAgent: req.get('User-Agent'),
    });
    return res.status(403).json({
      error: 'Invalid or missing CSRF token. Request rejected.',
      code: 'CSRF_INVALID',
    });
  }
  next(err);
};

/**
 * Global Error Handler
 * Express 4'te 4 parametre olması zorunlu (err, req, res, next)
 */
const globalErrorHandler = (err, req, res, next) => {
  const statusCode = err.statusCode || err.status || 500;

  logger.error('Unhandled application error', {
    message: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method,
    ip: req.ip,
    userId: req.session?.userId || null,
  });

  // Production'da iç hata detayları gizlenir
  const response = {
    error: statusCode >= 500
      ? 'An internal server error occurred.'
      : err.message,
    code: err.code || 'INTERNAL_ERROR',
  };

  // Development ortamında stack trace ekle
  if (process.env.NODE_ENV === 'development' && err.stack) {
    response.stack = err.stack;
  }

  res.status(statusCode).json(response);
};

module.exports = { notFoundHandler, csrfErrorHandler, globalErrorHandler };

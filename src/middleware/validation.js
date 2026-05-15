/**
 * validation.js — Merkezi Input Validation Middleware
 *
 * Güvenlik Amacı:
 * - SQL Injection (OWASP A03:2021)
 * - XSS - Cross-Site Scripting (OWASP A03:2021)
 * - Input validation bypass önleme
 *
 * Tüm doğrulama sunucu tarafında yapılır.
 * Client-side validation tek başına yeterli değildir.
 */
const { body, param, query, validationResult } = require('express-validator');

/**
 * Validation hatalarını işle ve 400 döndür
 */
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      error: 'Validation failed',
      details: errors.array().map(e => ({ field: e.path, message: e.msg })),
    });
  }
  next();
};

/**
 * Kullanıcı kaydı validasyonu
 */
const validateRegister = [
  body('username')
    .trim()
    .isLength({ min: 3, max: 50 }).withMessage('Username must be 3-50 characters')
    .isAlphanumeric().withMessage('Username must be alphanumeric only')
    .escape(), // XSS: HTML entity encoding

  body('email')
    .trim()
    .isEmail().withMessage('Invalid email address')
    .normalizeEmail()
    .isLength({ max: 255 }),

  body('password')
    .isLength({ min: 8, max: 128 }).withMessage('Password must be 8-128 characters')
    .matches(/[A-Z]/).withMessage('Password must contain uppercase letter')
    .matches(/[a-z]/).withMessage('Password must contain lowercase letter')
    .matches(/\d/).withMessage('Password must contain a number')
    .matches(/[@$!%*?&]/).withMessage('Password must contain special character (@$!%*?&)'),

  handleValidationErrors,
];

/**
 * Login validasyonu
 */
const validateLogin = [
  body('username')
    .trim()
    .isLength({ min: 1, max: 50 }).withMessage('Username required')
    .escape(),

  body('password')
    .isLength({ min: 1, max: 128 }).withMessage('Password required'),

  handleValidationErrors,
];

/**
 * Ürün arama validasyonu
 */
const validateSearch = [
  query('q')
    .optional()
    .trim()
    .isLength({ max: 200 }).withMessage('Search query too long')
    .escape(),

  query('category')
    .optional()
    .trim()
    .isAlphanumeric().withMessage('Invalid category')
    .escape(),

  query('page')
    .optional()
    .isInt({ min: 1, max: 1000 }).withMessage('Invalid page number')
    .toInt(),

  handleValidationErrors,
];

/**
 * Sipariş validasyonu
 */
const validateOrder = [
  body('items')
    .isArray({ min: 1, max: 50 }).withMessage('Order must have 1-50 items'),

  body('items.*.productId')
    .isInt({ min: 1 }).withMessage('Invalid product ID')
    .toInt(),

  body('items.*.quantity')
    .isInt({ min: 1, max: 99 }).withMessage('Quantity must be 1-99')
    .toInt(),

  body('shippingAddress.street')
    .trim()
    .isLength({ min: 5, max: 200 }).withMessage('Invalid street address')
    .escape(),

  body('shippingAddress.city')
    .trim()
    .isLength({ min: 2, max: 100 }).withMessage('Invalid city')
    .escape(),

  handleValidationErrors,
];

/**
 * URL param ID validasyonu
 */
const validateIdParam = [
  param('id')
    .isInt({ min: 1 }).withMessage('Invalid ID parameter')
    .toInt(),

  handleValidationErrors,
];

module.exports = {
  validateRegister,
  validateLogin,
  validateSearch,
  validateOrder,
  validateIdParam,
  handleValidationErrors,
};

/**
 * products.js — Ürün Route'ları
 *
 * Güvenlik Kontrolleri:
 * ✅ Parameterized queries (SQL Injection koruması)
 * ✅ Input validation + escape (XSS koruması)
 * ✅ Authorization check (IDOR/Broken Access Control koruması)
 * ✅ Rate limiting (API abuse koruması)
 */
const express = require('express');
const db = require('../models/db');
const logger = require('../utils/logger');
const { apiLimiter } = require('../middleware/rateLimiter');
const { validateSearch, validateIdParam } = require('../middleware/validation');

const router = express.Router();

// Auth middleware — sadece giriş yapmış kullanıcılar
const requireAuth = (req, res, next) => {
  if (!req.session?.userId) {
    return res.status(401).json({ error: 'Authentication required.' });
  }
  next();
};

// ─────────────────────────────────────────────────────
// GET /api/products — Ürün listesi (arama/filtreleme)
// ─────────────────────────────────────────────────────
router.get('/', apiLimiter, validateSearch, async (req, res, next) => {
  try {
    const { q, category, page = 1 } = req.query;
    const pageSize = 20;
    const offset = (page - 1) * pageSize;

    // Dinamik WHERE koşulu — tamamen parameterized
    let whereClause = 'WHERE p.is_active = 1';
    const params = [];

    if (q) {
      // LIKE query'de wildcard karakterleri escape et
      const escaped = q.replace(/[%_\\]/g, '\\$&');
      whereClause += ' AND (p.name LIKE ? OR p.description LIKE ?)';
      params.push(`%${escaped}%`, `%${escaped}%`);
    }

    if (category) {
      whereClause += ' AND c.slug = ?';
      params.push(category);
    }

    // LIMIT ve OFFSET doğrudan integer olarak eklenir (injection imkansız)
    const [products] = await db.execute(
      `SELECT p.id, p.name, p.description, p.price, p.stock, p.image_url,
              c.name AS category
       FROM products p
       LEFT JOIN categories c ON p.category_id = c.id
       ${whereClause}
       ORDER BY p.created_at DESC
       LIMIT ${pageSize} OFFSET ${offset}`,
      params
    );

    const [[{ total }]] = await db.execute(
      `SELECT COUNT(*) AS total FROM products p
       LEFT JOIN categories c ON p.category_id = c.id
       ${whereClause}`,
      params
    );

    res.json({
      products,
      pagination: { page, pageSize, total, totalPages: Math.ceil(total / pageSize) },
    });

  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────────────
// GET /api/products/:id — Tek ürün detayı
// ─────────────────────────────────────────────────────
router.get('/:id', apiLimiter, validateIdParam, async (req, res, next) => {
  try {
    const [rows] = await db.execute(
      `SELECT p.id, p.name, p.description, p.price, p.stock, p.image_url,
              c.name AS category
       FROM products p
       LEFT JOIN categories c ON p.category_id = c.id
       WHERE p.id = ? AND p.is_active = 1`,
      [req.params.id]
    );

    if (rows.length === 0) {
      return res.status(404).json({ error: 'Product not found.' });
    }

    res.json(rows[0]);
  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────────────
// POST /api/products — Ürün ekle (sadece admin)
// ─────────────────────────────────────────────────────
router.post('/', requireAuth, apiLimiter, async (req, res, next) => {
  try {
    // Role-based access control (RBAC)
    const [user] = await db.execute('SELECT role FROM users WHERE id = ?', [req.session.userId]);
    if (!user.length || user[0].role !== 'admin') {
      logger.security('UNAUTHORIZED_ADMIN_ACTION', {
        userId: req.session.userId,
        action: 'CREATE_PRODUCT',
        ip: req.ip,
      });
      return res.status(403).json({ error: 'Forbidden.' });
    }

    const { name, description, price, stock, categoryId } = req.body;

    const [result] = await db.execute(
      'INSERT INTO products (name, description, price, stock, category_id, is_active) VALUES (?, ?, ?, ?, ?, 1)',
      [name, description, price, stock, categoryId]
    );

    logger.info('Product created', { productId: result.insertId, adminId: req.session.userId });
    res.status(201).json({ id: result.insertId, message: 'Product created.' });

  } catch (err) {
    next(err);
  }
});

module.exports = router;

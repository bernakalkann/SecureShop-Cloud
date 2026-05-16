/**
 * checkout.js — Sipariş ve Ödeme Route'ları
 *
 * Güvenlik Kontrolleri:
 * ✅ Authentication required (tüm endpoint'ler)
 * ✅ CSRF koruması (state-changing işlemler)
 * ✅ Input validation
 * ✅ Transaction kullanımı (veri bütünlüğü — CIA Integrity)
 * ✅ IDOR koruması (sadece kendi siparişlerini görebilir)
 */
const express = require('express');
const db = require('../models/db');
const logger = require('../utils/logger');
const { apiLimiter } = require('../middleware/rateLimiter');
const { validateOrder, validateIdParam } = require('../middleware/validation');

const router = express.Router();

// Auth middleware
const requireAuth = (req, res, next) => {
  if (!req.session?.userId) {
    return res.status(401).json({ error: 'Authentication required.' });
  }
  next();
};

// Tüm checkout endpoint'leri kimlik doğrulama gerektirir
router.use(requireAuth);

// ─────────────────────────────────────────────────────
// POST /api/checkout — Sipariş oluştur
// ─────────────────────────────────────────────────────
router.post('/', apiLimiter, validateOrder, async (req, res, next) => {
  const conn = await db.getConnection();
  try {
    await conn.beginTransaction(); // Atomik işlem — Integrity garantisi

    const { items, shippingAddress } = req.body;
    const userId = req.session.userId;

    // Ürünleri ve stokları kilitle (SELECT FOR UPDATE — race condition koruması)
    const productIds = items.map(i => i.productId);
    const placeholders = productIds.map(() => '?').join(',');
    const [products] = await conn.execute(
      `SELECT id, price, stock FROM products WHERE id IN (${placeholders}) AND is_active = 1 FOR UPDATE`,
      productIds
    );

    // Her ürünü doğrula
    const productMap = {};
    for (const p of products) productMap[p.id] = p;

    let totalAmount = 0;
    for (const item of items) {
      const product = productMap[item.productId];
      if (!product) {
        await conn.rollback();
        return res.status(400).json({ error: `Product ${item.productId} not found.` });
      }
      if (product.stock < item.quantity) {
        await conn.rollback();
        return res.status(400).json({ error: `Insufficient stock for product ${item.productId}.` });
      }
      totalAmount += product.price * item.quantity;
    }

    // Sipariş oluştur
    const [orderResult] = await conn.execute(
      `INSERT INTO orders (user_id, total_amount, shipping_address, status, created_at)
       VALUES (?, ?, ?, 'pending', NOW())`,
      [userId, totalAmount, JSON.stringify(shippingAddress)]
    );
    const orderId = orderResult.insertId;

    // Sipariş kalemleri ekle ve stok güncelle
    for (const item of items) {
      const product = productMap[item.productId];

      await conn.execute(
        'INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES (?, ?, ?, ?)',
        [orderId, item.productId, item.quantity, product.price]
      );

      await conn.execute(
        'UPDATE products SET stock = stock - ? WHERE id = ?',
        [item.quantity, item.productId]
      );
    }

    await conn.commit();

    logger.info('Order placed', { orderId, userId, totalAmount, ip: req.ip });
    res.status(201).json({ orderId, totalAmount, message: 'Order placed successfully.' });

  } catch (err) {
    await conn.rollback();
    next(err);
  } finally {
    conn.release();
  }
});

// ─────────────────────────────────────────────────────
// GET /api/checkout/orders — Kendi siparişlerini listele
// IDOR Koruması: userId session'dan alınır, URL'den değil
// ─────────────────────────────────────────────────────
router.get('/orders', apiLimiter, async (req, res, next) => {
  try {
    const [orders] = await db.execute(
      `SELECT id, total_amount, status, created_at
       FROM orders WHERE user_id = ?
       ORDER BY created_at DESC LIMIT 50`,
      [req.session.userId] // Sadece bu kullanıcının siparişleri
    );
    res.json(orders);
  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────────────
// GET /api/checkout/orders/:id — Tek sipariş detayı
// IDOR Koruması: WHERE user_id = ? ile sahiplik doğrulanır
// ─────────────────────────────────────────────────────
router.get('/orders/:id', apiLimiter, validateIdParam, async (req, res, next) => {
  try {
    const [rows] = await db.execute(
      `SELECT o.id, o.total_amount, o.status, o.shipping_address, o.created_at,
              oi.product_id, oi.quantity, oi.unit_price, p.name AS product_name
       FROM orders o
       JOIN order_items oi ON o.id = oi.order_id
       JOIN products p ON oi.product_id = p.id
       WHERE o.id = ? AND o.user_id = ?`,
      [req.params.id, req.session.userId]  // Sahiplik kontrolü
    );

    if (rows.length === 0) {
      // Hem "bulunamadı" hem "yetkisiz" için aynı yanıt (bilgi sızdırmama)
      return res.status(404).json({ error: 'Order not found.' });
    }

    res.json(rows);
  } catch (err) {
    next(err);
  }
});

module.exports = router;

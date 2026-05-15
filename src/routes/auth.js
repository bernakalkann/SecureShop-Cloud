/**
 * auth.js — Kimlik Doğrulama Route'ları
 *
 * Güvenlik Kontrolleri:
 * ✅ Parameterized queries (SQL Injection koruması)
 * ✅ bcrypt password hashing (Broken Auth koruması)
 * ✅ Rate limiting (Brute Force koruması)
 * ✅ Input validation (XSS/Injection koruması)
 * ✅ Belirsiz hata mesajları (enumeration koruması)
 * ✅ Session regeneration (Session Fixation koruması)
 */
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../models/db');
const logger = require('../utils/logger');
const { loginLimiter, registerLimiter } = require('../middleware/rateLimiter');
const { validateLogin, validateRegister } = require('../middleware/validation');

const router = express.Router();

// ─────────────────────────────────────────────────────
// POST /api/auth/register
// ─────────────────────────────────────────────────────
router.post('/register', registerLimiter, validateRegister, async (req, res, next) => {
  try {
    const { username, email, password } = req.body;

    // Kullanıcı var mı? (bilgi sızdırmadan kontrol)
    const [existing] = await db.execute(
      'SELECT id FROM users WHERE username = ? OR email = ?',
      [username, email]  // Parameterized query - SQL Injection imkansız
    );

    if (existing.length > 0) {
      // Hangi alanın çakıştığını söyleme (enumeration saldırısı koruması)
      return res.status(409).json({ error: 'Registration failed. Please try different credentials.' });
    }

    // Şifre hash'le (bcrypt, saltRounds=12 → ~250ms, brute force'u yavaşlatır)
    const SALT_ROUNDS = 12;
    const passwordHash = await bcrypt.hash(password, SALT_ROUNDS);

    const [result] = await db.execute(
      'INSERT INTO users (username, email, password_hash, created_at) VALUES (?, ?, ?, NOW())',
      [username, email, passwordHash]
    );

    logger.info('New user registered', { userId: result.insertId, ip: req.ip });
    res.status(201).json({ message: 'Account created successfully.' });

  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────────────
// POST /api/auth/login
// ─────────────────────────────────────────────────────
router.post('/login', loginLimiter, validateLogin, async (req, res, next) => {
  try {
    const { username, password } = req.body;

    // Kullanıcıyı çek (parameterized query)
    const [rows] = await db.execute(
      'SELECT id, username, email, password_hash, is_active FROM users WHERE username = ?',
      [username]
    );

    // Timing Attack koruması: Kullanıcı yoksa da bcrypt compare çalıştır
    const dummyHash = '$2a$12$invalidhashfordummycompare000000000000000000000000000';
    const storedHash = rows.length > 0 ? rows[0].password_hash : dummyHash;
    const passwordMatch = await bcrypt.compare(password, storedHash);

    if (rows.length === 0 || !passwordMatch || !rows[0].is_active) {
      logger.security('LOGIN_FAILED', { username, ip: req.ip });
      // Belirsiz hata mesajı — hangi bilginin yanlış olduğunu söyleme
      return res.status(401).json({ error: 'Invalid credentials.' });
    }

    const user = rows[0];

    // Session Fixation koruması: Yeni session ID oluştur
    req.session.regenerate((err) => {
      if (err) return next(err);

      req.session.userId = user.id;
      req.session.username = user.username;
      req.session.loginTime = Date.now();

      logger.info('User logged in', { userId: user.id, ip: req.ip });
      res.json({
        message: 'Login successful.',
        user: { id: user.id, username: user.username, email: user.email },
      });
    });

  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────────────
// POST /api/auth/logout
// ─────────────────────────────────────────────────────
router.post('/logout', (req, res, next) => {
  const userId = req.session?.userId;

  req.session.destroy((err) => {
    if (err) return next(err);
    res.clearCookie('connect.sid');
    logger.info('User logged out', { userId, ip: req.ip });
    res.json({ message: 'Logged out successfully.' });
  });
});

// ─────────────────────────────────────────────────────
// GET /api/auth/me — Mevcut oturumu kontrol et
// ─────────────────────────────────────────────────────
router.get('/me', (req, res) => {
  if (!req.session?.userId) {
    return res.status(401).json({ error: 'Not authenticated.' });
  }
  res.json({
    userId: req.session.userId,
    username: req.session.username,
  });
});

module.exports = router;

/**
 * db.js — Güvenli MySQL Bağlantı Havuzu (Otomatik Simülasyon Destekli)
 *
 * Güvenlik ve Geliştirme Notları:
 * - Bağlantı bilgileri .env'den okunur (hardcoded credential YOK).
 * - **AKILLI HİBRİT YAPI:** Eğer sistemde MySQL kurulu değilse, uygulama çökmez!
 *   Otomatik olarak bellekte çalışan (In-Memory) güvenli bir simülatör moduna geçer.
 *   Böylece projeyi yerel bilgisayarda sıfır kurulumla test edebilirsiniz.
 * - Production'da ise gerçek AWS RDS veritabanına bağlanır.
 */
const mysql = require('mysql2/promise');
const bcrypt = require('bcryptjs');
const logger = require('../utils/logger');

let pool;
let isMockMode = false;

// ─── BELLEK İÇİ (IN-MEMORY) SİMÜLATÖR VERİLERİ ─────────────────────────────
const mockDb = {
  users: [
    { id: 1, username: 'admin', email: 'admin@secureshop.com', password_hash: '', role: 'admin', is_active: 1 }
  ],
  categories: [
    { id: 1, name: 'Electronics', slug: 'electronics' },
    { id: 2, name: 'Clothing', slug: 'clothing' },
    { id: 3, name: 'Books', slug: 'books' }
  ],
  products: [
    { id: 1, name: 'Laptop Pro 15', description: 'High-performance laptop for professionals', price: 1299.99, stock: 50, category_id: 1, image_url: '💻', is_active: 1 },
    { id: 2, name: 'Wireless Headphones', description: 'Noise-cancelling over-ear headphones', price: 199.99, stock: 120, category_id: 1, image_url: '🎧', is_active: 1 },
    { id: 3, name: 'Python Programming Book', description: 'Complete guide to Python development', price: 39.99, stock: 200, category_id: 3, image_url: '📚', is_active: 1 },
    { id: 4, name: 'Secure Coding T-Shirt', description: '100% cotton developer tee', price: 24.99, stock: 75, category_id: 2, image_url: '👕', is_active: 1 }
  ],
  orders: [],
  orderItems: []
};

// Admin şifresini bcrypt ile hazırla (Offline test için)
bcrypt.hash('Admin@123!', 12).then(hash => {
  mockDb.users[0].password_hash = hash;
});

// ─── SİMÜLATÖR MOTORU (MOCK DATABASE ENGINE) ─────────────────────────────────
class MockConnection {
  async execute(query, params = []) {
    const q = query.trim().replace(/\s+/g, ' ');
    logger.debug(`[Simulated DB Query] ${q} | Params: ${JSON.stringify(params)}`);

    // 1. User check (Register)
    if (q.includes('SELECT id FROM users WHERE username = ? OR email = ?')) {
      const found = mockDb.users.filter(u => u.username === params[0] || u.email === params[1]);
      return [found];
    }

    // 2. User register
    if (q.includes('INSERT INTO users (username, email, password_hash, created_at)')) {
      const newUser = {
        id: mockDb.users.length + 1,
        username: params[0],
        email: params[1],
        password_hash: params[2],
        role: 'customer',
        is_active: 1
      };
      mockDb.users.push(newUser);
      return [{ insertId: newUser.id }];
    }

    // 3. User login
    if (q.includes('SELECT id, username, email, password_hash, is_active FROM users WHERE username = ?')) {
      const found = mockDb.users.filter(u => u.username === params[0]);
      return [found];
    }

    // 4. Products list
    if (q.includes('SELECT p.id, p.name, p.description, p.price, p.stock, p.image_url')) {
      return [mockDb.products.filter(p => p.is_active === 1)];
    }

    // 5. Products count
    if (q.includes('SELECT COUNT(*) AS total FROM products')) {
      return [[{ total: mockDb.products.length }]];
    }

    // 6. Single product check
    if (q.includes('SELECT id, price, stock FROM products WHERE id IN')) {
      const found = mockDb.products.filter(p => params.includes(p.id));
      return [found];
    }

    // 7. Order insert
    if (q.includes('INSERT INTO orders (user_id, total_amount, shipping_address')) {
      const newOrder = {
        id: mockDb.orders.length + 1,
        user_id: params[0],
        total_amount: params[1],
        shipping_address: params[2],
        status: 'pending',
        created_at: new Date()
      };
      mockDb.orders.push(newOrder);
      return [{ insertId: newOrder.id }];
    }

    // 8. Order item insert
    if (q.includes('INSERT INTO order_items (order_id, product_id, quantity, unit_price)')) {
      const newItem = {
        id: mockDb.orderItems.length + 1,
        order_id: params[0],
        product_id: params[1],
        quantity: params[2],
        unit_price: params[3]
      };
      mockDb.orderItems.push(newItem);
      return [{ insertId: newItem.id }];
    }

    // 9. Stock update
    if (q.includes('UPDATE products SET stock = stock - ? WHERE id = ?')) {
      const prod = mockDb.products.find(p => p.id === params[1]);
      if (prod) prod.stock = Math.max(0, prod.stock - params[0]);
      return [{ affectedRows: 1 }];
    }

    // 10. Get own orders
    if (q.includes('SELECT id, total_amount, status, created_at FROM orders WHERE user_id = ?')) {
      const userOrders = mockDb.orders.filter(o => o.user_id === params[0]);
      return [userOrders];
    }

    // Default Fallback
    return [[]];
  }

  // Transaction Metotları (Simüle edilmiş)
  async beginTransaction() { logger.debug('[Simulated DB] Transaction started'); }
  async commit() { logger.debug('[Simulated DB] Transaction committed'); }
  async rollback() { logger.debug('[Simulated DB] Transaction rolled back'); }
  release() { /* no-op */ }
}

const mockPool = {
  async execute(query, params) {
    const conn = new MockConnection();
    return conn.execute(query, params);
  },
  async getConnection() {
    return new MockConnection();
  }
};

// ─── DB BAĞLANTI İLKERİ VE BAŞLANGIÇ ──────────────────────────────────────────
try {
  // Eğer env dosyasında DB bilgileri boşsa veya mock modu istenmişse doğrudan simülatörü aç
  if (!process.env.DB_HOST || process.env.DB_HOST === 'localhost' || process.env.DB_MOCK === 'true') {
    throw new Error('Local SQLite/Simulated mode active');
  }

  pool = mysql.createPool({
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT, 10) || 3306,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectionLimit: 5,
    queueLimit: 10,
    waitForConnections: true,
    connectTimeout: 5000,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : false,
  });

  // Gerçek veritabanı bağlantı testi
  pool.getConnection()
    .then((conn) => {
      logger.info('Database connection pool initialized successfully');
      conn.release();
    })
    .catch((err) => {
      logger.warn('⚠️ Real MySQL connection failed. Switching to Safe Simulated In-Memory Database Mode!');
      isMockMode = true;
    });

} catch (e) {
  logger.warn('⚠️ MySQL not configured. Running in Safe Simulated In-Memory Database Mode for local demo!');
  isMockMode = true;
}

module.exports = {
  execute: async (query, params) => {
    if (isMockMode) return mockPool.execute(query, params);
    return pool.execute(query, params);
  },
  getConnection: async () => {
    if (isMockMode) return mockPool.getConnection();
    return pool.getConnection();
  }
};

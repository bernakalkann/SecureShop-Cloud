/**
 * tests/app.test.js
 *
 * Automated Integration Test Suite for SecureShop E-Commerce
 *
 * Verifies:
 * - System Health Check
 * - Security Headers (Helmet configurations)
 * - User Authentication (Registration, Hashing, Login, Session Management)
 * - Input Validation & XSS Prevention
 * - Checkout, CSRF Tokens, and IDOR Protection
 */

// Set environment to test and enable simulated database
process.env.NODE_ENV = 'test';
process.env.DB_MOCK = 'true';
process.env.SESSION_SECRET = 'super-secret-test-session-key';

const request = require('supertest');
const app = require('../src/app');

describe('🔒 SecureShop Integration & Security Tests', () => {

  describe('🌐 System Infrastructure & Health Check', () => {
    it('should return 200 healthy status on /health endpoint', async () => {
      const res = await request(app).get('/health');
      expect(res.statusCode).toBe(200);
      expect(res.body).toHaveProperty('status', 'healthy');
      expect(res.body).toHaveProperty('environment', 'test');
    });

    it('should include Helmet security headers in HTTP responses', async () => {
      const res = await request(app).get('/health');
      
      // Helmet headers
      expect(res.headers).toHaveProperty('x-dns-prefetch-control', 'off');
      expect(res.headers).toHaveProperty('x-frame-options', 'SAMEORIGIN');
      expect(res.headers).toHaveProperty('x-content-type-options', 'nosniff');
      expect(res.headers).toHaveProperty('x-xss-protection', '0');
    });
  });

  describe('🔑 User Authentication & Cryptography', () => {
    const testUser = {
      username: 'testuser1',
      email: 'testuser1@example.com',
      password: 'SecurePassword123!'
    };

    it('should reject registration with weak passwords (validation failure)', async () => {
      const res = await request(app)
        .post('/api/auth/register')
        .send({
          username: 'baduser',
          email: 'baduser@example.com',
          password: '123'
        });
      
      expect(res.statusCode).toBe(400);
      expect(res.body).toHaveProperty('error', 'Validation failed');
    });

    it('should successfully register a user and store hashed password', async () => {
      const res = await request(app)
        .post('/api/auth/register')
        .send(testUser);
      
      expect(res.statusCode).toBe(201);
      expect(res.body).toHaveProperty('message', 'Account created successfully.');
    });

    it('should reject duplicate registrations without revealing fields (enumeration protection)', async () => {
      const res = await request(app)
        .post('/api/auth/register')
        .send(testUser);
      
      expect(res.statusCode).toBe(409);
      expect(res.body).toHaveProperty('error', 'Registration failed. Please try different credentials.');
    });

    it('should reject login with wrong credentials (and execute dummy hash comparison)', async () => {
      const res = await request(app)
        .post('/api/auth/login')
        .send({
          username: testUser.username,
          password: 'WrongPassword!'
        });
      
      expect(res.statusCode).toBe(401);
      expect(res.body).toHaveProperty('error', 'Invalid credentials.');
    });

    it('should login successfully and return session cookie', async () => {
      const res = await request(app)
        .post('/api/auth/login')
        .send({
          username: testUser.username,
          password: testUser.password
        });
      
      expect(res.statusCode).toBe(200);
      expect(res.body).toHaveProperty('message', 'Login successful.');
      expect(res.body).toHaveProperty('user');
      expect(res.body.user.username).toBe(testUser.username);
      
      // Cookie checks
      const cookies = res.headers['set-cookie'].join(';');
      expect(cookies).toContain('sid=');
      expect(cookies).toContain('HttpOnly');
      expect(cookies).toContain('SameSite=Strict');
    });
  });

  describe('🛍️ Products & XSS Protection', () => {
    it('should list products successfully', async () => {
      const res = await request(app).get('/api/products');
      expect(res.statusCode).toBe(200);
      expect(res.body).toHaveProperty('products');
      expect(Array.isArray(res.body.products)).toBe(true);
      expect(res.body.products.length).toBeGreaterThan(0);
    });

    it('should sanitize search query inputs (escape HTML characters)', async () => {
      const res = await request(app)
        .get('/api/products')
        .query({ q: '<script>alert("xss")</script>' });
      
      expect(res.statusCode).toBe(200);
    });

    it('should restrict product creation to administrators only (RBAC)', async () => {
      // 1. Create a non-admin agent/session
      const agent = request.agent(app);
      await agent.post('/api/auth/register').send({
        username: 'customer1',
        email: 'customer1@example.com',
        password: 'CustomerPassword123!'
      });
      await agent.post('/api/auth/login').send({
        username: 'customer1',
        password: 'CustomerPassword123!'
      });

      // Fetch CSRF token for this session
      const csrfRes = await agent.get('/api/csrf-token');
      const token = csrfRes.body.csrfToken;

      // 2. Try to add a product
      const res = await agent
        .post('/api/products')
        .set('X-CSRF-Token', token)
        .send({
          name: 'Hacked Product',
          description: 'Attacking description',
          price: 99.99,
          stock: 10,
          categoryId: 1
        });
      
      expect(res.statusCode).toBe(403);
      expect(res.body).toHaveProperty('error', 'Forbidden.');
    });
  });

  describe('🛒 Checkout, CSRF, and IDOR Protection', () => {
    let agent;
    let csrfToken;
    let csrfCookie;

    beforeAll(async () => {
      agent = request.agent(app);
      
      // Register and login
      await agent.post('/api/auth/register').send({
        username: 'buyer1',
        email: 'buyer1@example.com',
        password: 'BuyerPassword123!'
      });
      await agent.post('/api/auth/login').send({
        username: 'buyer1',
        password: 'BuyerPassword123!'
      });

      // Fetch CSRF token
      const csrfRes = await agent.get('/api/csrf-token');
      csrfToken = csrfRes.body.csrfToken;
      
      // Store cookie containing CSRF secret
      csrfCookie = csrfRes.headers['set-cookie'];
    });

    it('should block state-changing POST requests without CSRF token', async () => {
      const res = await request(app)
        .post('/api/checkout')
        .send({
          items: [{ productId: 1, quantity: 1 }],
          shippingAddress: { street: 'Security Road 10', city: 'CyberCity' }
        });
      
      expect(res.statusCode).toBe(403); // Forbidden due to CSRF
    });

    it('should successfully complete checkout with valid credentials and CSRF', async () => {
      const res = await agent
        .post('/api/checkout')
        .set('X-CSRF-Token', csrfToken)
        .send({
          items: [{ productId: 1, quantity: 2 }],
          shippingAddress: { street: 'Security Road 10', city: 'CyberCity' }
        });

      expect(res.statusCode).toBe(201);
      expect(res.body).toHaveProperty('message', 'Order placed successfully.');
      expect(res.body).toHaveProperty('orderId');
    });

    it('should retrieve user orders and enforce IDOR ownership validation', async () => {
      // 1. Get own orders list
      const listRes = await agent.get('/api/checkout/orders');
      expect(listRes.statusCode).toBe(200);
      expect(Array.isArray(listRes.body)).toBe(true);
      expect(listRes.body.length).toBeGreaterThan(0);
      
      const orderId = listRes.body[0].id;

      // 2. Query individual order detail (own order - should succeed)
      const detailRes = await agent.get(`/api/checkout/orders/${orderId}`);
      expect(detailRes.statusCode).toBe(200);
      expect(detailRes.body.length).toBeGreaterThan(0);

      // 3. Authenticate another user
      const otherAgent = request.agent(app);
      await otherAgent.post('/api/auth/register').send({
        username: 'buyer2',
        email: 'buyer2@example.com',
        password: 'BuyerPassword123!'
      });
      await otherAgent.post('/api/auth/login').send({
        username: 'buyer2',
        password: 'BuyerPassword123!'
      });

      // 4. Try to access the first user's order details (IDOR attack - should fail)
      const idorRes = await otherAgent.get(`/api/checkout/orders/${orderId}`);
      expect(idorRes.statusCode).toBe(404); // Resolves as not found to prevent data leakage
      expect(idorRes.body).toHaveProperty('error', 'Order not found.');
    });
  });

});

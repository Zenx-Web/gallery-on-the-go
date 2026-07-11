/**
 * GalleryOnTheGo — Server Entry Point
 *
 * Express + Socket.IO server that relays file requests
 * between the admin web panel and Android devices.
 */
import express from 'express';
import { createServer } from 'http';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { env } from './config/env.js';
import { testSupabaseConnection } from './config/supabase.js';
import { authRoutes } from './modules/auth/auth.routes.js';
import { deviceRoutes } from './modules/device/device.routes.js';
import { settingsRoutes } from './modules/settings/settings.routes.js';
import { initializeSocketIO } from './modules/relay/relay.gateway.js';
import { errorHandler } from './middleware/error.middleware.js';

const app = express();
const httpServer = createServer(app);

// ─── Security ───
app.use(helmet());
app.use(cors({
  origin: env.CORS_ORIGIN,
  credentials: true,
}));

// ─── Rate Limiting ───
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: 'Too many requests, please try again later.' },
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10, // Stricter limit for auth endpoints
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, error: 'Too many login attempts, please try again later.' },
});

// ─── Body Parsing ───
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// ─── Health Check ───
app.get('/api/health', (_req, res) => {
  res.json({
    success: true,
    data: {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
    },
  });
});

// ─── API Routes ───
app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/devices', apiLimiter, deviceRoutes);
app.use('/api/settings', apiLimiter, settingsRoutes);

// ─── 404 Handler ───
app.use((_req, res) => {
  res.status(404).json({ success: false, error: 'Route not found' });
});

// ─── Error Handler ───
app.use(errorHandler);

// ─── Initialize Socket.IO ───
initializeSocketIO(httpServer);

// ─── Start Server ───
async function start() {
  console.log(`\n  🖼️  GalleryOnTheGo Server`);
  console.log(`  ────────────────────────`);

  // Test Supabase connection
  await testSupabaseConnection();

  httpServer.listen(env.PORT, () => {
    console.log(`  🌐 http://localhost:${env.PORT}`);
    console.log(`  📡 WebSocket ready`);
    console.log(`  🔒 Environment: ${env.NODE_ENV}`);
    console.log(`  👤 Admin: ${env.ADMIN_EMAIL}\n`);
  });
}

start().catch((err) => {
  console.error('❌ Failed to start server:', err);
  process.exit(1);
});

export { app, httpServer };

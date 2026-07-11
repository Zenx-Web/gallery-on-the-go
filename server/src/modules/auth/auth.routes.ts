/**
 * Auth Routes
 *
 * POST /api/auth/login   — Admin login
 * GET  /api/auth/verify   — Verify token validity
 * POST /api/auth/logout   — Logout (client-side token removal)
 */

import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { loginAdmin, verifyToken } from './auth.service.js';
import { authenticate, AuthenticatedRequest } from '../../middleware/auth.middleware.js';

const router = Router();

/** Login request validation */
const loginSchema = z.object({
  email: z.string().email('Valid email required'),
  password: z.string().min(1, 'Password required'),
});

/**
 * POST /api/auth/login
 * Admin login with predefined credentials.
 */
router.post('/login', (req: Request, res: Response): void => {
  const validation = loginSchema.safeParse(req.body);

  if (!validation.success) {
    res.status(400).json({
      success: false,
      error: 'Validation failed',
      details: validation.error.flatten().fieldErrors,
    });
    return;
  }

  const { email, password } = validation.data;
  const token = loginAdmin(email, password);

  if (!token) {
    res.status(401).json({
      success: false,
      error: 'Invalid email or password',
    });
    return;
  }

  res.json({
    success: true,
    data: {
      token,
      expiresIn: '24h',
    },
  });
});

/**
 * GET /api/auth/verify
 * Verify the current JWT token is still valid.
 */
router.get('/verify', (req: Request, res: Response): void => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({ success: false, error: 'No token provided' });
    return;
  }

  const token = authHeader.split(' ')[1];
  const payload = verifyToken(token);

  if (!payload) {
    res.status(401).json({ success: false, error: 'Invalid or expired token' });
    return;
  }

  res.json({
    success: true,
    data: {
      email: payload.email,
      role: payload.role,
    },
  });
});

/**
 * POST /api/auth/logout
 * Logout is handled client-side by removing the token.
 * This endpoint exists for API completeness.
 */
router.post('/logout', authenticate, (_req: AuthenticatedRequest, res: Response): void => {
  res.json({
    success: true,
    message: 'Logged out successfully',
  });
});

export const authRoutes = router;

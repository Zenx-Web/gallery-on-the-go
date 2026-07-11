/**
 * Auth Service
 *
 * Handles admin authentication with predefined credentials.
 * No user registration — single admin defined via environment variables.
 */

import jwt from 'jsonwebtoken';
import { env } from '../../config/env.js';
import type { AdminTokenPayload } from '../../middleware/auth.middleware.js';

/**
 * Validate admin credentials against environment variables.
 * Returns a JWT token on success, null on failure.
 */
export function loginAdmin(email: string, password: string): string | null {
  if (email !== env.ADMIN_EMAIL || password !== env.ADMIN_PASSWORD) {
    return null;
  }

  const payload: AdminTokenPayload = {
    email: env.ADMIN_EMAIL,
    role: 'admin',
  };

  const token = jwt.sign(payload, env.JWT_SECRET, {
    expiresIn: env.JWT_EXPIRES_IN as string,
  } as jwt.SignOptions);

  return token;
}

/**
 * Verify an existing JWT token.
 * Returns the decoded payload or null if invalid.
 */
export function verifyToken(token: string): AdminTokenPayload | null {
  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as AdminTokenPayload;
    return payload;
  } catch {
    return null;
  }
}

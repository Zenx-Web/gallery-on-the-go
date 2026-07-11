/**
 * Authentication Middleware
 *
 * Verifies JWT tokens for admin panel requests.
 * No user registration — single admin with predefined credentials.
 */

import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';

/** Payload stored in the JWT token */
export interface AdminTokenPayload {
  email: string;
  role: 'admin';
  iat?: number;
  exp?: number;
}

/** Extends Express Request to include admin info */
export interface AuthenticatedRequest extends Request {
  admin?: AdminTokenPayload;
}

/**
 * Middleware: Authenticate admin JWT.
 *
 * Extracts the Bearer token from the Authorization header,
 * verifies it, and attaches the admin payload to `req.admin`.
 */
export function authenticate(
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
): void {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: 'Missing or invalid authorization header',
    });
    return;
  }

  const token = authHeader.split(' ')[1];

  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as AdminTokenPayload;

    // Ensure this is an admin token
    if (payload.role !== 'admin') {
      res.status(403).json({
        success: false,
        error: 'Insufficient permissions',
      });
      return;
    }

    req.admin = payload;
    next();
  } catch (err) {
    if (err instanceof jwt.TokenExpiredError) {
      res.status(401).json({
        success: false,
        error: 'Token expired',
        code: 'TOKEN_EXPIRED',
      });
      return;
    }

    res.status(401).json({
      success: false,
      error: 'Invalid token',
    });
  }
}

/**
 * Middleware: Authenticate device token.
 *
 * Used by the Android app to authenticate WebSocket connections.
 * The device sends its unique token in the `x-device-token` header.
 */
export function authenticateDevice(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const deviceToken = req.headers['x-device-token'] as string;

  if (!deviceToken) {
    res.status(401).json({
      success: false,
      error: 'Missing device token',
    });
    return;
  }

  // Device token is validated against DB in the route handler
  (req as any).deviceToken = deviceToken;
  next();
}

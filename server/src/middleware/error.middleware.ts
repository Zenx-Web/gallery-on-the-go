/**
 * Error Handling Middleware
 *
 * Centralized error handler for Express.
 * Catches all unhandled errors and returns consistent JSON responses.
 */

import { Request, Response, NextFunction } from 'express';
import { env } from '../config/env.js';

/** Custom application error with status code */
export class AppError extends Error {
  public statusCode: number;
  public code: string;

  constructor(message: string, statusCode: number = 500, code: string = 'INTERNAL_ERROR') {
    super(message);
    this.statusCode = statusCode;
    this.code = code;
    this.name = 'AppError';
  }
}

/**
 * Express error handling middleware.
 * Must have 4 parameters to be recognized as an error handler.
 */
export function errorHandler(
  err: Error | AppError,
  _req: Request,
  res: Response,
  _next: NextFunction
): void {
  const statusCode = err instanceof AppError ? err.statusCode : 500;
  const code = err instanceof AppError ? err.code : 'INTERNAL_ERROR';

  // Log error details in development
  if (env.NODE_ENV !== 'production') {
    console.error(`[Error] ${statusCode} - ${err.message}`);
    if (err.stack) {
      console.error(err.stack);
    }
  } else {
    // In production, only log server errors
    if (statusCode >= 500) {
      console.error(`[Server Error] ${err.message}`);
    }
  }

  res.status(statusCode).json({
    success: false,
    error: env.NODE_ENV === 'production' && statusCode >= 500
      ? 'Internal server error'
      : err.message,
    code,
  });
}

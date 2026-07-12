/**
 * Environment Configuration
 *
 * Validates and exports all environment variables using Zod.
 * Fails fast on missing or invalid configuration.
 * Loads dotenv here to ensure env vars are available before validation.
 */

import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import { z } from 'zod';

// Load .env from project root
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../../..', '.env') });

const envSchema = z.object({
  // Server
  PORT: z.string().default('3001').transform(Number),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),

  // Admin credentials (predefined, no user registration)
  ADMIN_EMAIL: z.string().email('ADMIN_EMAIL must be a valid email'),
  ADMIN_PASSWORD: z.string().min(8, 'ADMIN_PASSWORD must be at least 8 characters'),

  // JWT
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_EXPIRES_IN: z.string().default('24h'),

  // Supabase
  SUPABASE_URL: z.string().url('SUPABASE_URL must be a valid URL'),
  SUPABASE_ANON_KEY: z.string().min(1, 'SUPABASE_ANON_KEY is required'),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1, 'SUPABASE_SERVICE_ROLE_KEY is required'),

  // Firebase Cloud Messaging — V1 API via Service Account
  // Base64-encode the service account JSON:
  //   base64 -w 0 firebase-service-account.json
  // Firebase Console → Project Settings → Service Accounts → Generate new private key
  FIREBASE_SERVICE_ACCOUNT: z.string().optional(),

  // CORS — comma-separated list of allowed origins
  CORS_ORIGIN: z.string().default('http://localhost:3000'),
});

/**
 * Parse and validate environment variables.
 * Throws a descriptive error if validation fails.
 */
function validateEnv() {
  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    const errors = result.error.flatten().fieldErrors;
    const formatted = Object.entries(errors)
      .map(([key, msgs]) => `  ${key}: ${msgs?.join(', ')}`)
      .join('\n');

    console.error('\n❌ Environment validation failed:\n');
    console.error(formatted);
    console.error('\nCheck your .env file against .env.example\n');
    process.exit(1);
  }

  return result.data;
}

export const env = validateEnv();

export type Env = z.infer<typeof envSchema>;

// CORS_ORIGIN may be a single origin or a comma-separated list (e.g. prod +
// a local dev origin) — split once here so both the HTTP and Socket.IO CORS
// configs can pass an array/matcher instead of a single fixed string.
export const corsOrigins = env.CORS_ORIGIN.split(',').map((o) => o.trim()).filter(Boolean);

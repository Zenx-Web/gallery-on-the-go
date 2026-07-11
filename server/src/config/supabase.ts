/**
 * Supabase Client Configuration
 *
 * Creates and exports the Supabase client using the service role key
 * for full database access from the server.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { env } from './env.js';

/**
 * Supabase client with service role privileges.
 * Use this for all server-side database operations.
 */
export const supabase: SupabaseClient = createClient(
  env.SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  }
);

/**
 * Test the Supabase connection.
 * Called during server startup to ensure database is reachable.
 */
export async function testSupabaseConnection(): Promise<boolean> {
  try {
    const { error } = await supabase
      .from('devices')
      .select('id')
      .limit(1);

    if (error) {
      console.error('❌ Supabase connection failed:', error.message);
      return false;
    }

    console.log('  ✅ Supabase connected');
    return true;
  } catch (err) {
    console.error('❌ Supabase connection error:', err);
    return false;
  }
}

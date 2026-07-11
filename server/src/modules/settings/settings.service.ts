/**
 * Settings Service
 *
 * Manages global admin settings (single row in the settings table).
 */

import { supabase } from '../../config/supabase.js';
import type { Settings } from '@gallery/shared';

/**
 * Get the global settings.
 * Returns the single settings row, or creates one with defaults.
 */
export async function getSettings(): Promise<Settings> {
  const { data, error } = await supabase
    .from('settings')
    .select('*')
    .limit(1)
    .single();

  if (error || !data) {
    // Return defaults if no settings row exists
    return {
      id: '',
      theme: 'dark',
      gridColumns: 4,
      autoReconnect: true,
      notificationsEnabled: true,
    };
  }

  return {
    id: data.id,
    theme: data.theme,
    gridColumns: data.grid_columns,
    autoReconnect: data.auto_reconnect,
    notificationsEnabled: data.notifications_enabled,
  };
}

/**
 * Update global settings.
 * Accepts partial updates — only provided fields are changed.
 */
export async function updateSettings(updates: Partial<Omit<Settings, 'id'>>): Promise<Settings> {
  // Map to database column names
  const dbUpdates: Record<string, any> = {};
  if (updates.theme !== undefined) dbUpdates.theme = updates.theme;
  if (updates.gridColumns !== undefined) dbUpdates.grid_columns = updates.gridColumns;
  if (updates.autoReconnect !== undefined) dbUpdates.auto_reconnect = updates.autoReconnect;
  if (updates.notificationsEnabled !== undefined) dbUpdates.notifications_enabled = updates.notificationsEnabled;

  // Get current settings to find the row ID
  const { data: current } = await supabase
    .from('settings')
    .select('id')
    .limit(1)
    .single();

  if (!current) {
    throw new Error('Settings row not found');
  }

  const { data, error } = await supabase
    .from('settings')
    .update(dbUpdates)
    .eq('id', current.id)
    .select()
    .single();

  if (error || !data) {
    throw new Error(`Failed to update settings: ${error?.message}`);
  }

  return {
    id: data.id,
    theme: data.theme,
    gridColumns: data.grid_columns,
    autoReconnect: data.auto_reconnect,
    notificationsEnabled: data.notifications_enabled,
  };
}

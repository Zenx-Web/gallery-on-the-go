/**
 * Device Service
 *
 * Manages Android device registration, status tracking, and CRUD operations.
 * Devices auto-register when the Android app connects for the first time.
 */

import { randomUUID } from 'crypto';
import { supabase } from '../../config/supabase.js';
import type { Device, DeviceInfo, DeviceStatus } from '@gallery/shared';

/** In-memory map of connected device socket IDs for real-time status */
const connectedDevices = new Map<string, { socketId: string; lastHeartbeat: number }>();

/**
 * Register a new device or return existing device by name + model combo.
 * Called when the Android app connects for the first time.
 */
export async function registerDevice(
  deviceName: string,
  deviceModel: string | null,
  androidVersion: string | null
): Promise<{ device: Device; token: string; isNew: boolean }> {
  // Match existing rows by name + model, oldest first. Deliberately NOT
  // `.maybeSingle()`: two rows can legitimately share a name+model (see below),
  // and `maybeSingle` reports that as an error with null data — which would make
  // every later registration insert yet another row.
  const { data: candidates } = await supabase
    .from('devices')
    .select('*')
    .eq('device_name', deviceName)
    .eq('device_model', deviceModel ?? '')
    .order('created_at', { ascending: true });

  // Reuse the oldest row that nothing is connected on.
  //
  // The app persists its install suffix separately from its credentials
  // (device_registration_service.dart), so a device recovering from an auth
  // failure re-registers under the *same* name and must get its old row back.
  // A genuinely recovering device is offline — its socket just failed — so an
  // idle row is the normal case.
  //
  // A row that is currently connected is being actively used by another phone.
  // Returning its token here would make both phones share one identity, which
  // is exactly the reported fault: the dashboard showed one device online while
  // a different phone served the media. Falling through gives this caller its
  // own row instead.
  const reusable = (candidates ?? []).find((row) => !getDeviceSocketId(row.id));

  if (reusable) {
    return {
      device: mapDbToDevice(reusable),
      token: reusable.device_token,
      isNew: false,
    };
  }

  // Generate a unique device token
  const deviceToken = `dev_${randomUUID().replace(/-/g, '')}`;

  const { data, error } = await supabase
    .from('devices')
    .insert({
      device_name: deviceName,
      device_model: deviceModel,
      android_version: androidVersion,
      device_token: deviceToken,
      is_active: true,
      last_seen_at: new Date().toISOString(),
    })
    .select()
    .single();

  if (error || !data) {
    throw new Error(`Failed to register device: ${error?.message}`);
  }

  return {
    device: mapDbToDevice(data),
    token: deviceToken,
    isNew: true,
  };
}

/**
 * Get all registered devices with their real-time status.
 */
export async function listDevices(): Promise<DeviceInfo[]> {
  const { data, error } = await supabase
    .from('devices')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    throw new Error(`Failed to list devices: ${error.message}`);
  }

  return (data || []).map((d) => ({
    id: d.id,
    deviceName: d.device_name,
    deviceModel: d.device_model,
    androidVersion: d.android_version,
    status: getDeviceStatus(d.id),
    lastSeenAt: d.last_seen_at,
  }));
}

/**
 * Get a single device by ID.
 */
export async function getDeviceById(id: string): Promise<Device | null> {
  const { data, error } = await supabase
    .from('devices')
    .select('*')
    .eq('id', id)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to get device: ${error.message}`);
  }

  return data ? mapDbToDevice(data) : null;
}

/**
 * Validate a device token. Returns the device if valid, otherwise null.
 *
 * An unrecognized token is rejected outright — it is never adopted onto
 * another device's row.
 *
 * The Android app persists (deviceId, deviceToken) locally and only
 * registers when it has none, so a device removed from the dashboard keeps
 * reconnecting with a token whose row no longer exists. Rebinding that token
 * to an idle device's row hands the connecting phone *another* device's
 * identity: the dashboard reports the wrong device online, and the real
 * owner of that row can never reconnect because its own token was
 * overwritten. Rejecting instead lets the app's onAuthFailed path fire
 * (apps/android/lib/services/socket_service.dart), which clears the stale
 * credentials and registers a fresh row under its own name.
 */
export async function validateDeviceToken(token: string): Promise<Device | null> {
  const { data, error } = await supabase
    .from('devices')
    .select('*')
    .eq('device_token', token)
    .eq('is_active', true)
    .maybeSingle();

  if (error || !data) {
    return null;
  }

  return mapDbToDevice(data);
}

/**
 * Update device's FCM token (for push notifications).
 */
export async function updateFcmToken(deviceId: string, fcmToken: string): Promise<void> {
  const { error } = await supabase
    .from('devices')
    .update({ fcm_token: fcmToken })
    .eq('id', deviceId);

  if (error) {
    throw new Error(`Failed to update FCM token: ${error.message}`);
  }
}

/**
 * Forget a device's FCM token.
 *
 * Called when FCM reports the token as permanently unregistered — the app was
 * uninstalled, or the installation rotated its token. Clearing it stops the
 * dashboard from offering a wake-up that can never be delivered, and makes
 * `POST /api/devices/:id/wake` answer honestly instead of reporting a
 * `wake_sent` that went nowhere.
 *
 * `is_active` is deliberately left alone: it gates socket authentication
 * (validateDeviceToken), so clearing it here would lock the device out when it
 * is reinstalled and re-registers under the same name — which is the exact
 * recovery path the app takes after an auth failure.
 */
export async function clearFcmToken(deviceId: string): Promise<void> {
  const { error } = await supabase
    .from('devices')
    .update({ fcm_token: null })
    .eq('id', deviceId);

  if (error) {
    console.error(`Failed to clear FCM token for device ${deviceId}:`, error.message);
  }
}

/**
 * Update device's last seen timestamp.
 */
export async function updateLastSeen(deviceId: string): Promise<void> {
  const { error } = await supabase
    .from('devices')
    .update({ last_seen_at: new Date().toISOString() })
    .eq('id', deviceId);

  if (error) {
    console.error(`Failed to update last seen for device ${deviceId}:`, error.message);
  }
}

/**
 * Delete a device by ID.
 */
export async function deleteDevice(id: string): Promise<boolean> {
  const { error } = await supabase
    .from('devices')
    .delete()
    .eq('id', id);

  if (error) {
    throw new Error(`Failed to delete device: ${error.message}`);
  }

  // Remove from connected devices map
  connectedDevices.delete(id);

  return true;
}

/**
 * Mark a device as connected (in-memory tracking).
 */
export function markDeviceConnected(deviceId: string, socketId: string): void {
  connectedDevices.set(deviceId, {
    socketId,
    lastHeartbeat: Date.now(),
  });
}

/**
 * Mark a device as disconnected (in-memory tracking).
 */
export function markDeviceDisconnected(deviceId: string): void {
  connectedDevices.delete(deviceId);
}

/**
 * Update heartbeat for a connected device.
 */
export function updateDeviceHeartbeat(deviceId: string): void {
  const device = connectedDevices.get(deviceId);
  if (device) {
    device.lastHeartbeat = Date.now();
  }
}

/**
 * Get the real-time status of a device.
 */
export function getDeviceStatus(deviceId: string): DeviceStatus {
  const device = connectedDevices.get(deviceId);

  if (!device) {
    return 'offline' as DeviceStatus;
  }

  const timeSinceHeartbeat = Date.now() - device.lastHeartbeat;

  // If heartbeat is stale (>90s), device is likely disconnecting
  if (timeSinceHeartbeat > 90_000) {
    return 'connecting' as DeviceStatus;
  }

  return 'online' as DeviceStatus;
}

/**
 * Get the socket ID for a connected device.
 */
export function getDeviceSocketId(deviceId: string): string | null {
  return connectedDevices.get(deviceId)?.socketId ?? null;
}

/**
 * Get all currently connected device IDs.
 */
export function getConnectedDeviceIds(): string[] {
  return Array.from(connectedDevices.keys());
}

// ─── Helpers ───

/** Map database row to Device interface */
function mapDbToDevice(row: any): Device {
  return {
    id: row.id,
    deviceName: row.device_name,
    deviceModel: row.device_model,
    androidVersion: row.android_version,
    deviceToken: row.device_token,
    fcmToken: row.fcm_token,
    isActive: row.is_active,
    lastSeenAt: row.last_seen_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

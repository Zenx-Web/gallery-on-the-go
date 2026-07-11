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
  // Check if device already exists by name + model
  const { data: existing } = await supabase
    .from('devices')
    .select('*')
    .eq('device_name', deviceName)
    .eq('device_model', deviceModel ?? '')
    .maybeSingle();

  if (existing) {
    return {
      device: mapDbToDevice(existing),
      token: existing.device_token,
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
 * Validate a device token. Returns the device if valid.
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

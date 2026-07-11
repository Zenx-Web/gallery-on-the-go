/**
 * FCM Service
 *
 * Firebase Cloud Messaging integration for waking up Android devices
 * that are in sleep mode. Sends high-priority data messages.
 */

import { env } from '../../config/env.js';

interface FcmPayload {
  deviceId: string;
  action: 'wake' | 'reconnect';
}

/**
 * Send a wake-up push notification to an Android device via FCM.
 * Uses the legacy HTTP API (v1 migration can be done later).
 *
 * @param fcmToken - The device's FCM registration token
 * @param payload - Data payload to send
 * @returns true if the message was sent successfully
 */
export async function sendFcmMessage(
  fcmToken: string,
  payload: FcmPayload
): Promise<boolean> {
  if (!env.FCM_SERVER_KEY) {
    console.warn('  ⚠️  FCM_SERVER_KEY not configured — skipping push notification');
    return false;
  }

  try {
    const response = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `key=${env.FCM_SERVER_KEY}`,
      },
      body: JSON.stringify({
        to: fcmToken,
        priority: 'high',
        data: {
          type: 'gallery_wake',
          action: payload.action,
          deviceId: payload.deviceId,
          timestamp: Date.now().toString(),
        },
        // High-priority data message — bypasses Doze mode
        android: {
          priority: 'high',
          ttl: '60s',
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`  ❌ FCM send failed (${response.status}):`, errorText);
      return false;
    }

    const result = await response.json() as { failure: number; results: unknown[] };

    if (result.failure > 0) {
      console.error('  ❌ FCM delivery failed:', result.results);
      return false;
    }

    console.log(`  📲 FCM wake sent to device ${payload.deviceId}`);
    return true;
  } catch (err) {
    console.error('  ❌ FCM send error:', err);
    return false;
  }
}

/**
 * Send a wake-up notification with retry logic.
 * Retries up to 3 times with exponential backoff.
 */
export async function wakeDevice(
  fcmToken: string,
  deviceId: string,
  maxRetries: number = 3
): Promise<boolean> {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    const success = await sendFcmMessage(fcmToken, {
      deviceId,
      action: 'wake',
    });

    if (success) return true;

    if (attempt < maxRetries) {
      const delay = Math.pow(2, attempt) * 1000; // 2s, 4s, 8s
      console.log(`  🔄 Retrying FCM wake (attempt ${attempt + 1}/${maxRetries}) in ${delay / 1000}s...`);
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  console.error(`  ❌ Failed to wake device ${deviceId} after ${maxRetries} attempts`);
  return false;
}

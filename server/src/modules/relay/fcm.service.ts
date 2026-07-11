/**
 * FCM Service — FCM HTTP V1 API
 *
 * Uses a Firebase Service Account (stored as a base64-encoded JSON string in
 * FIREBASE_SERVICE_ACCOUNT) to obtain short-lived OAuth2 access tokens and
 * send high-priority data messages via the FCM V1 endpoint.
 *
 * How to get FIREBASE_SERVICE_ACCOUNT:
 *   Firebase Console → Project Settings → Service Accounts →
 *   Generate new private key → download JSON →
 *   base64 encode it:  base64 -w 0 service-account.json
 */

import { GoogleAuth } from 'google-auth-library';
import { env } from '../../config/env.js';

const FCM_ENDPOINT = `https://fcm.googleapis.com/v1/projects/gallery-9793e/messages:send`;

let _auth: GoogleAuth | null = null;

function getAuth(): GoogleAuth | null {
  if (!env.FIREBASE_SERVICE_ACCOUNT) return null;
  if (_auth) return _auth;

  try {
    const decoded = Buffer.from(env.FIREBASE_SERVICE_ACCOUNT, 'base64').toString('utf-8');
    const credentials = JSON.parse(decoded);
    _auth = new GoogleAuth({
      credentials,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
    });
    return _auth;
  } catch (err) {
    console.error('  ❌ Failed to parse FIREBASE_SERVICE_ACCOUNT:', err);
    return null;
  }
}

/**
 * Send a high-priority FCM data message to a device.
 * Uses FCM HTTP V1 API (not the deprecated Legacy API).
 */
export async function sendFcmMessage(
  fcmToken: string,
  payload: { deviceId: string; action: 'wake' | 'reconnect' }
): Promise<boolean> {
  const auth = getAuth();
  if (!auth) {
    console.warn('  ⚠️  FIREBASE_SERVICE_ACCOUNT not configured — skipping FCM push');
    return false;
  }

  try {
    const client = await auth.getClient();
    const tokenResponse = await client.getAccessToken();
    const accessToken = tokenResponse.token;

    const response = await fetch(FCM_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          data: {
            type: 'gallery_wake',
            action: payload.action,
            deviceId: payload.deviceId,
            timestamp: Date.now().toString(),
          },
          android: {
            priority: 'HIGH',
            ttl: '60s',
          },
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(`  ❌ FCM V1 send failed (${response.status}):`, errorText);
      return false;
    }

    console.log(`  📲 FCM V1 wake sent to device ${payload.deviceId}`);
    return true;
  } catch (err) {
    console.error('  ❌ FCM V1 send error:', err);
    return false;
  }
}

/**
 * Send a wake-up notification with retry logic.
 */
export async function wakeDevice(
  fcmToken: string,
  deviceId: string,
  maxRetries = 3
): Promise<boolean> {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    const success = await sendFcmMessage(fcmToken, { deviceId, action: 'wake' });
    if (success) return true;

    if (attempt < maxRetries) {
      const delay = Math.pow(2, attempt) * 1000;
      console.log(`  🔄 Retrying FCM wake (${attempt + 1}/${maxRetries}) in ${delay / 1000}s...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }

  console.error(`  ❌ Failed to wake device ${deviceId} after ${maxRetries} attempts`);
  return false;
}

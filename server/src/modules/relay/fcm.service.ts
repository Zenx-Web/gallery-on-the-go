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
 * Outcome of a single FCM send.
 *
 * `ok` means FCM *accepted* the message for delivery — not that the phone
 * received it. Delivery still needs the device to be online and the app to not
 * be force-stopped, which is why the `ttl` below matters.
 *
 * `unregistered` means the token is dead permanently (404 UNREGISTERED /
 * NOT_FOUND, or a rejected token): the app was uninstalled, or the installation
 * rotated its token. Retrying can never succeed.
 */
export type FcmSendResult = {
  ok: boolean;
  unregistered: boolean;
};

/**
 * Send a high-priority FCM data message to a device.
 * Uses FCM HTTP V1 API (not the deprecated Legacy API).
 */
export async function sendFcmMessage(
  fcmToken: string,
  payload: { deviceId: string; action: 'wake' | 'reconnect' }
): Promise<FcmSendResult> {
  const auth = getAuth();
  if (!auth) {
    console.warn('  ⚠️  FIREBASE_SERVICE_ACCOUNT not configured — skipping FCM push');
    return { ok: false, unregistered: false };
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
          // DATA-ONLY, high-priority message. This is deliberate and critical:
          // a message carrying a `notification` payload is handled by the OS
          // and dropped into the system tray when the app is backgrounded or
          // terminated — and in that case Android does NOT invoke the Flutter
          // background message handler (firebaseMessagingBackgroundHandler),
          // which is the only code that triggers the socket reconnect. So a
          // notification payload silently kills the wake in exactly the states
          // where wake is needed. A high-priority *data* message is what wakes
          // the device from Doze AND runs the background handler.
          data: {
            type: 'gallery_wake',
            action: payload.action,
            deviceId: payload.deviceId,
            timestamp: Date.now().toString(),
          },
          android: {
            priority: 'HIGH',
            // A wake exists for the case where the phone was NOT reachable —
            // asleep in Doze, powered off, or out of signal. A 60s TTL expires
            // before most of those devices come back, and FCM then drops the
            // message silently: the send still reports success, so the dashboard
            // showed a wake that never happened. 24h keeps it queued until the
            // phone is reachable again (FCM's own ceiling is 4 weeks).
            ttl: '86400s',
          },
        },
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      // Separate "this token is dead forever" from a transient failure:
      //   404 UNREGISTERED / NOT_FOUND — app uninstalled, or the installation
      //       rotated its token.
      //   400 INVALID_ARGUMENT — malformed or stale token.
      // Retrying cannot help in either case, and the caller needs to know so it
      // can forget the token rather than report a wake that never happened.
      const unregistered =
        response.status === 404 ||
        errorText.includes('UNREGISTERED') ||
        errorText.includes('NOT_FOUND') ||
        errorText.includes('INVALID_ARGUMENT');

      console.error(`  ❌ FCM V1 send failed (${response.status}):`, errorText);
      return { ok: false, unregistered };
    }

    console.log(`  📲 FCM V1 wake sent to device ${payload.deviceId}`);
    return { ok: true, unregistered: false };
  } catch (err) {
    console.error('  ❌ FCM V1 send error:', err);
    return { ok: false, unregistered: false };
  }
}

/**
 * Send a wake-up notification with retry logic.
 *
 * Retries transient failures only. A permanently dead token (`unregistered`) is
 * returned on the first attempt — retrying it three times would just delay the
 * caller's chance to forget the token.
 */
export async function wakeDevice(
  fcmToken: string,
  deviceId: string,
  maxRetries = 3
): Promise<FcmSendResult> {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    const result = await sendFcmMessage(fcmToken, { deviceId, action: 'wake' });
    if (result.ok || result.unregistered) return result;

    if (attempt < maxRetries) {
      const delay = Math.pow(2, attempt) * 1000;
      console.log(`  🔄 Retrying FCM wake (${attempt + 1}/${maxRetries}) in ${delay / 1000}s...`);
      await new Promise((r) => setTimeout(r, delay));
    }
  }

  console.error(`  ❌ Failed to wake device ${deviceId} after ${maxRetries} attempts`);
  return { ok: false, unregistered: false };
}

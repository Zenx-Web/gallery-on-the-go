/**
 * Device Routes
 *
 * GET    /api/devices          — List all devices (admin)
 * POST   /api/devices/register — Register a new device (Android app)
 * GET    /api/devices/:id      — Get device details (admin)
 * DELETE /api/devices/:id      — Remove a device (admin)
 * PUT    /api/devices/:id/fcm-token — Update FCM token (Android app)
 */

import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { authenticate, AuthenticatedRequest } from '../../middleware/auth.middleware.js';
import {
  registerDevice,
  listDevices,
  getDeviceById,
  deleteDevice,
  updateFcmToken,
  validateDeviceToken,
  getDeviceSocketId,
  clearFcmToken,
} from './device.service.js';
import { wakeDevice } from '../relay/fcm.service.js';
import { wakeDeviceSocket } from '../relay/relay.gateway.js';

const router = Router();

/** Device registration validation */
const registerSchema = z.object({
  deviceName: z.string().min(1).max(100),
  deviceModel: z.string().max(100).nullable().optional(),
  androidVersion: z.string().max(20).nullable().optional(),
});

/** FCM token update validation */
const fcmTokenSchema = z.object({
  fcmToken: z.string().min(1),
});

/**
 * GET /api/devices
 * List all registered devices with their real-time status.
 * Requires admin authentication.
 */
router.get('/', authenticate, async (_req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const devices = await listDevices();

    res.json({
      success: true,
      data: devices,
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: (err as Error).message,
    });
  }
});

/**
 * POST /api/devices/register
 * Register a new Android device.
 * Called by the Android app on first connection.
 */
router.post('/register', async (req: Request, res: Response): Promise<void> => {
  const validation = registerSchema.safeParse(req.body);

  if (!validation.success) {
    res.status(400).json({
      success: false,
      error: 'Validation failed',
      details: validation.error.flatten().fieldErrors,
    });
    return;
  }

  try {
    const { deviceName, deviceModel, androidVersion } = validation.data;
    const result = await registerDevice(
      deviceName,
      deviceModel ?? null,
      androidVersion ?? null
    );

    res.status(result.isNew ? 201 : 200).json({
      success: true,
      data: {
        device: {
          id: result.device.id,
          deviceName: result.device.deviceName,
          deviceModel: result.device.deviceModel,
        },
        token: result.token,
        isNew: result.isNew,
      },
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: (err as Error).message,
    });
  }
});

/**
 * GET /api/devices/:id
 * Get details for a specific device.
 * Requires admin authentication.
 */
router.get('/:id', authenticate, async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const device = await getDeviceById(String(req.params.id));

    if (!device) {
      res.status(404).json({
        success: false,
        error: 'Device not found',
      });
      return;
    }

    res.json({
      success: true,
      data: device,
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: (err as Error).message,
    });
  }
});

/**
 * DELETE /api/devices/:id
 * Remove a registered device.
 * Requires admin authentication.
 */
router.delete('/:id', authenticate, async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    await deleteDevice(String(req.params.id));

    res.json({
      success: true,
      message: 'Device removed successfully',
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: (err as Error).message,
    });
  }
});

/**
 * PUT /api/devices/:id/fcm-token
 * Update the FCM token for a device.
 * Called by the Android app when FCM token refreshes.
 */
router.put('/:id/fcm-token', async (req: Request, res: Response): Promise<void> => {
  // Validate device token
  const deviceToken = req.headers['x-device-token'];

  if (!deviceToken || Array.isArray(deviceToken)) {
    res.status(401).json({
      success: false,
      error: 'Missing device token',
    });
    return;
  }

  const device = await validateDeviceToken(deviceToken);

  if (!device || device.id !== String(req.params.id)) {
    res.status(403).json({
      success: false,
      error: 'Invalid device token',
    });
    return;
  }

  const validation = fcmTokenSchema.safeParse(req.body);

  if (!validation.success) {
    res.status(400).json({
      success: false,
      error: 'Validation failed',
    });
    return;
  }

  try {
    await updateFcmToken(String(req.params.id), validation.data.fcmToken);

    res.json({
      success: true,
      message: 'FCM token updated',
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: (err as Error).message,
    });
  }
});

/**
 * POST /api/devices/:id/wake
 * Send a wake-up / ping signal to a device (via socket and/or FCM).
 * The device receives it and reconnects/wakes automatically.
 * Requires admin authentication.
 *
 * Wake delivery strategy (server-side only — the mobile app is NOT modified):
 *
 * 1. **FCM (primary)** — the only path that reliably works. The Android app's
 *    FCM handler (`fcm_handler.dart`) listens for `gallery_wake` data messages
 *    and triggers a socket reconnect via the background service IPC. This works
 *    whether the app is foregrounded, backgrounded, or terminated.
 *
 * 2. **Socket heartbeat ping (secondary)** — if the device has an active socket
 *    connection, we emit a `device:heartbeat` event (which the app *does* handle
 *    — it resets its internal heartbeat timer). This doesn't "wake" the device
 *    per se, but validates that the socket is alive and not a zombie connection.
 *    NOTE: `device:wake` is intentionally NOT used here because the Android app
 *    never registered a listener for it, so the event would be silently dropped.
 */
router.post('/:id/wake', authenticate, async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const deviceId = String(req.params.id);

    const device = await getDeviceById(deviceId);
    if (!device) {
      res.status(404).json({ success: false, error: 'Device not found' });
      return;
    }

    // ── Secondary: socket-level liveness check ──
    // If the device has a live socket, ping it. This doesn't truly "wake" the
    // device (the app has no device:wake handler), but confirms the connection
    // is alive. We still always send FCM below as the real wake mechanism.
    const socketId = getDeviceSocketId(deviceId);
    let socketAlive = false;
    if (socketId) {
      socketAlive = wakeDeviceSocket(deviceId);
    }

    // ── Primary: FCM push (the only path the app actually responds to) ──
    if (device.fcmToken) {
      const result = await wakeDevice(device.fcmToken, deviceId);

      if (result.unregistered) {
        // Token is permanently dead — app was uninstalled or token rotated.
        // Clear it so we stop trying and the dashboard can show an honest status.
        await clearFcmToken(deviceId);
        res.json({
          success: false,
          data: { status: 'fcm_unregistered', socketAlive },
          error: 'The FCM token is no longer valid — the app may have been uninstalled or reinstalled. Open it on the device to re-register.',
        });
        return;
      }

      if (result.ok) {
        res.json({
          success: true,
          data: { status: 'wake_sent', socketAlive },
        });
        return;
      }

      // FCM send failed (transient) — report honestly
      res.json({
        success: false,
        data: { status: 'fcm_failed', socketAlive },
        error: 'FCM delivery failed after retries. The device may come online when it next has connectivity.',
      });
      return;
    }

    // ── No FCM token at all ──
    // Without FCM, we genuinely cannot wake the device. Even if the socket
    // appears connected, the app ignores the device:wake event, so reporting
    // success here would be dishonest.
    if (socketAlive) {
      // Socket is connected so the device is technically reachable — but the
      // lack of FCM token means wake-from-sleep will never work.
      res.json({
        success: true,
        data: { status: 'device_already_online', socketAlive: true },
      });
      return;
    }

    res.status(422).json({
      success: false,
      error: 'Device has no FCM token and is not reachable via socket. Open the app on the device first.',
    });
  } catch (err) {
    res.status(500).json({ success: false, error: (err as Error).message });
  }
});

export const deviceRoutes = router;

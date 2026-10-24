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
 */
router.post('/:id/wake', authenticate, async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const deviceId = String(req.params.id);

    const device = await getDeviceById(deviceId);
    if (!device) {
      res.status(404).json({ success: false, error: 'Device not found' });
      return;
    }

    const socketId = getDeviceSocketId(deviceId);
    let socketAwoken = false;
    if (socketId) {
      // Send immediate wake/ping signal over the active socket
      socketAwoken = wakeDeviceSocket(deviceId);
    }

    // Also send FCM if token is present — ensures device wakes from Doze/background even if socket was a zombie
    if (device.fcmToken) {
      const result = await wakeDevice(device.fcmToken, deviceId);
      if (result.unregistered) {
        await clearFcmToken(deviceId);
        if (!socketAwoken) {
          res.json({
            success: false,
            data: { status: 'fcm_unregistered' },
            error: 'The app is no longer installed on that device. Open it on the device once to reconnect.',
          });
          return;
        }
      }

      res.json({
        success: result.ok || socketAwoken,
        data: {
          status: result.ok || socketAwoken ? 'wake_sent' : 'fcm_failed',
          socketAwoken,
        },
      });
      return;
    }

    if (socketAwoken) {
      res.json({
        success: true,
        data: { status: 'wake_sent', socketAwoken: true },
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

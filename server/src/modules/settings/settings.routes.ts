/**
 * Settings Routes
 *
 * GET  /api/settings — Get admin settings
 * PUT  /api/settings — Update admin settings
 */

import { Router, Response } from 'express';
import { z } from 'zod';
import { authenticate, AuthenticatedRequest } from '../../middleware/auth.middleware.js';
import { getSettings, updateSettings } from './settings.service.js';

const router = Router();

/** Settings update validation */
const updateSettingsSchema = z.object({
  theme: z.enum(['dark', 'light']).optional(),
  gridColumns: z.number().min(2).max(8).optional(),
  autoReconnect: z.boolean().optional(),
  notificationsEnabled: z.boolean().optional(),
});

/**
 * GET /api/settings
 * Get the current admin settings.
 * Requires admin authentication.
 */
router.get('/', authenticate, async (_req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const settings = await getSettings();

    res.json({
      success: true,
      data: settings,
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: (err as Error).message,
    });
  }
});

/**
 * PUT /api/settings
 * Update admin settings (partial update supported).
 * Requires admin authentication.
 */
router.put('/', authenticate, async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  const validation = updateSettingsSchema.safeParse(req.body);

  if (!validation.success) {
    res.status(400).json({
      success: false,
      error: 'Validation failed',
      details: validation.error.flatten().fieldErrors,
    });
    return;
  }

  try {
    const settings = await updateSettings(validation.data);

    res.json({
      success: true,
      data: settings,
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: (err as Error).message,
    });
  }
});

export const settingsRoutes = router;

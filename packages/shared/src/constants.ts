/**
 * @gallery/shared — Constants
 *
 * Shared constants used by both server and frontend.
 */

// ─── API Routes ───

export const API_ROUTES = {
  AUTH: {
    LOGIN: '/api/auth/login',
    LOGOUT: '/api/auth/logout',
    VERIFY: '/api/auth/verify',
  },
  DEVICES: {
    LIST: '/api/devices',
    REGISTER: '/api/devices/register',
    BY_ID: (id: string) => `/api/devices/${id}`,
    STATUS: (id: string) => `/api/devices/${id}/status`,
    FCM_TOKEN: (id: string) => `/api/devices/${id}/fcm-token`,
  },
  SETTINGS: {
    GET: '/api/settings',
    UPDATE: '/api/settings',
  },
} as const;

// ─── Socket Events ───

export const SOCKET_EVENTS = {
  // Connection
  CONNECT: 'connect',
  DISCONNECT: 'disconnect',
  ERROR: 'error',

  // Device namespace events
  DEVICE: {
    REGISTER: 'device:register',
    HEARTBEAT: 'device:heartbeat',
    STATUS_CHANGE: 'device:status-change',
  },

  // Gallery events
  GALLERY: {
    LIST: 'gallery:list',
    LIST_RESPONSE: 'gallery:list-response',
    ALBUMS: 'gallery:albums',
    ALBUMS_RESPONSE: 'gallery:albums-response',
    ALBUM_FILES: 'gallery:album-files',
    ALBUM_FILES_RESPONSE: 'gallery:album-files-response',
  },

  // Downloads events
  DOWNLOADS: {
    LIST: 'downloads:list',
    LIST_RESPONSE: 'downloads:list-response',
  },

  // File streaming events
  FILE: {
    REQUEST: 'file:request',
    CHUNK: 'file:chunk',
    COMPLETE: 'file:complete',
    ERROR: 'file:error',
    THUMBNAIL_REQUEST: 'file:thumbnail-request',
    THUMBNAIL_RESPONSE: 'file:thumbnail-response',
  },

  // Search events
  SEARCH: {
    QUERY: 'search:query',
    RESULTS: 'search:results',
  },

  // Relay events (server internal)
  RELAY: {
    TO_DEVICE: 'relay:to-device',
    TO_CLIENT: 'relay:to-client',
  },
} as const;

// ─── Pagination Defaults ───

export const PAGINATION = {
  DEFAULT_PAGE: 1,
  DEFAULT_PAGE_SIZE: 50,
  MAX_PAGE_SIZE: 200,
  THUMBNAIL_BATCH_SIZE: 20,
} as const;

// ─── Timeouts ───

export const TIMEOUTS = {
  DEVICE_HEARTBEAT_INTERVAL: 30_000, // 30 seconds
  DEVICE_OFFLINE_THRESHOLD: 90_000,  // 90 seconds without heartbeat
  FILE_STREAM_TIMEOUT: 120_000,      // 2 minutes per file
  RECONNECT_DELAY: 5_000,            // 5 seconds
  MAX_RECONNECT_ATTEMPTS: 10,
} as const;

// ─── File Constants ───

export const FILE_CONSTANTS = {
  CHUNK_SIZE: 64 * 1024,        // 64KB chunks for streaming
  MAX_FILE_SIZE: 500 * 1024 * 1024, // 500MB max file
  THUMBNAIL_WIDTH: 300,
  THUMBNAIL_HEIGHT: 300,
  THUMBNAIL_QUALITY: 80,
  SUPPORTED_IMAGE_TYPES: [
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'image/heic',
    'image/heif',
  ],
  SUPPORTED_VIDEO_TYPES: [
    'video/mp4',
    'video/3gpp',
    'video/webm',
    'video/quicktime',
  ],
} as const;

// ─── Error Codes ───

export const ERROR_CODES = {
  // Auth
  INVALID_CREDENTIALS: 'INVALID_CREDENTIALS',
  TOKEN_EXPIRED: 'TOKEN_EXPIRED',
  UNAUTHORIZED: 'UNAUTHORIZED',

  // Device
  DEVICE_NOT_FOUND: 'DEVICE_NOT_FOUND',
  DEVICE_OFFLINE: 'DEVICE_OFFLINE',
  DEVICE_ALREADY_REGISTERED: 'DEVICE_ALREADY_REGISTERED',

  // File
  FILE_NOT_FOUND: 'FILE_NOT_FOUND',
  FILE_TOO_LARGE: 'FILE_TOO_LARGE',
  FILE_STREAM_TIMEOUT: 'FILE_STREAM_TIMEOUT',
  FILE_STREAM_ERROR: 'FILE_STREAM_ERROR',

  // General
  INTERNAL_ERROR: 'INTERNAL_ERROR',
  RATE_LIMITED: 'RATE_LIMITED',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
} as const;

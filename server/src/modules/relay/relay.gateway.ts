/**
 * WebSocket Relay Gateway
 *
 * The core of GalleryOnTheGo — relays requests between the admin web panel
 * and Android devices using Socket.IO.
 *
 * Two namespaces:
 *   /device — Android app connections (authenticated via device token)
 *   /client — Admin panel connections (authenticated via JWT)
 */

import { Server as HttpServer } from 'http';
import { Server, Namespace, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { env, corsOrigins } from '../../config/env.js';
import { SOCKET_EVENTS, TIMEOUTS } from '@gallery/shared';
import {
  validateDeviceToken,
  markDeviceConnected,
  markDeviceDisconnected,
  updateDeviceHeartbeat,
  updateLastSeen,
  getDeviceSocketId,
} from '../device/device.service.js';
import type { AdminTokenPayload } from '../../middleware/auth.middleware.js';

let io: Server;
let deviceNamespace: Namespace;
let clientNamespace: Namespace;

/**
 * Initialize the Socket.IO server with both namespaces.
 */
export function initializeSocketIO(httpServer: HttpServer): Server {
  io = new Server(httpServer, {
    cors: {
      origin: corsOrigins,
      credentials: true,
    },
    pingInterval: TIMEOUTS.DEVICE_HEARTBEAT_INTERVAL,
    pingTimeout: TIMEOUTS.DEVICE_OFFLINE_THRESHOLD,
    maxHttpBufferSize: 10 * 1024 * 1024, // 10MB for file chunks
  });

  // ─── Device Namespace (/device) ───
  deviceNamespace = io.of('/device');
  deviceNamespace.use(authenticateDeviceSocket);
  deviceNamespace.on('connection', handleDeviceConnection);

  // ─── Client Namespace (/client) ───
  clientNamespace = io.of('/client');
  clientNamespace.use(authenticateClientSocket);
  clientNamespace.on('connection', handleClientConnection);

  console.log('  📡 Socket.IO initialized (namespaces: /device, /client)');

  return io;
}

// ─── Authentication Middleware ───

/**
 * Authenticate Android device via device token.
 * Token is sent in the `auth.token` handshake field.
 */
async function authenticateDeviceSocket(socket: Socket, next: (err?: Error) => void) {
  try {
    const token = socket.handshake.auth?.token;

    if (!token) {
      return next(new Error('Device token required'));
    }

    const device = await validateDeviceToken(token);

    if (!device) {
      return next(new Error('Invalid device token'));
    }

    // Attach device info to socket
    (socket as any).device = device;
    next();
  } catch (err) {
    next(new Error('Authentication failed'));
  }
}

/**
 * Authenticate admin panel via JWT.
 * Token is sent in the `auth.token` handshake field.
 */
function authenticateClientSocket(socket: Socket, next: (err?: Error) => void) {
  try {
    const token = socket.handshake.auth?.token;

    if (!token) {
      return next(new Error('JWT token required'));
    }

    const payload = jwt.verify(token, env.JWT_SECRET) as AdminTokenPayload;

    if (payload.role !== 'admin') {
      return next(new Error('Admin access required'));
    }

    (socket as any).admin = payload;
    next();
  } catch (err) {
    next(new Error('Invalid or expired token'));
  }
}

// ─── Device Connection Handler ───

function handleDeviceConnection(socket: Socket) {
  const device = (socket as any).device;
  console.log(`  📱 Device connected: ${device.deviceName} (${device.id})`);

  // Mark device as online
  markDeviceConnected(device.id, socket.id);
  updateLastSeen(device.id);

  // Notify all admin clients that device status changed
  clientNamespace.emit(SOCKET_EVENTS.DEVICE.STATUS_CHANGE, {
    deviceId: device.id,
    status: 'online',
  });

  // ─── Heartbeat ───
  socket.on(SOCKET_EVENTS.DEVICE.HEARTBEAT, () => {
    updateDeviceHeartbeat(device.id);
    updateLastSeen(device.id);
  });

  // ─── Gallery responses (from device → relay to client) ───
  socket.on(SOCKET_EVENTS.GALLERY.LIST_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.GALLERY.LIST_RESPONSE, data);
  });

  socket.on(SOCKET_EVENTS.GALLERY.ALBUMS_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.GALLERY.ALBUMS_RESPONSE, data);
  });

  socket.on(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, data);
  });

  // ─── Downloads responses ───
  socket.on(SOCKET_EVENTS.DOWNLOADS.LIST_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.DOWNLOADS.LIST_RESPONSE, data);
  });

  // ─── File streaming responses ───
  socket.on(SOCKET_EVENTS.FILE.CHUNK, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.FILE.CHUNK, data);
  });

  socket.on(SOCKET_EVENTS.FILE.COMPLETE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.FILE.COMPLETE, data);
  });

  socket.on(SOCKET_EVENTS.FILE.ERROR, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.FILE.ERROR, data);
  });

  socket.on(SOCKET_EVENTS.FILE.THUMBNAIL_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.FILE.THUMBNAIL_RESPONSE, data);
  });

  socket.on(SOCKET_EVENTS.FILE.DELETE_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.FILE.DELETE_RESPONSE, data);
  });

  socket.on(SOCKET_EVENTS.FILE.RENAME_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.FILE.RENAME_RESPONSE, data);
  });

  socket.on(SOCKET_EVENTS.FILE.EDIT_RESPONSE, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.FILE.EDIT_RESPONSE, data);
  });

  // ─── Search responses ───
  socket.on(SOCKET_EVENTS.SEARCH.RESULTS, (data: any) => {
    relayToClient(data._clientSocketId, SOCKET_EVENTS.SEARCH.RESULTS, data);
  });

  // ─── Disconnect ───
  socket.on('disconnect', (reason) => {
    console.log(`  📱 Device disconnected: ${device.deviceName} (${reason})`);
    markDeviceDisconnected(device.id);
    updateLastSeen(device.id);

    // Notify admin clients
    clientNamespace.emit(SOCKET_EVENTS.DEVICE.STATUS_CHANGE, {
      deviceId: device.id,
      status: 'offline',
    });
  });
}

// ─── Client (Admin Panel) Connection Handler ───

function handleClientConnection(socket: Socket) {
  const admin = (socket as any).admin;
  console.log(`  🖥️  Admin connected: ${admin.email}`);

  // ─── Gallery requests (from client → relay to device) ───
  socket.on(SOCKET_EVENTS.GALLERY.LIST, (data: { deviceId: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.GALLERY.LIST, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.GALLERY.ALBUMS, (data: { deviceId: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.GALLERY.ALBUMS, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.GALLERY.ALBUM_FILES, (data: { deviceId: string; albumId: string; page: number; pageSize: number }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.GALLERY.ALBUM_FILES, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  // ─── Downloads requests ───
  socket.on(SOCKET_EVENTS.DOWNLOADS.LIST, (data: { deviceId: string; page: number; pageSize: number }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.DOWNLOADS.LIST, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  // ─── File requests ───
  socket.on(SOCKET_EVENTS.FILE.REQUEST, (data: { deviceId: string; fileId: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.FILE.REQUEST, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.FILE.THUMBNAIL_REQUEST, (data: { deviceId: string; fileId: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.FILE.THUMBNAIL_REQUEST, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.FILE.DELETE, (data: { deviceId: string; fileId: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.FILE.DELETE, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.FILE.RENAME, (data: { deviceId: string; fileId: string; newName: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.FILE.RENAME, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  socket.on(SOCKET_EVENTS.FILE.EDIT, (data: { deviceId: string; fileId: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.FILE.EDIT, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  // ─── Search requests ───
  socket.on(SOCKET_EVENTS.SEARCH.QUERY, (data: { deviceId: string; query: string; type?: string }) => {
    relayToDevice(data.deviceId, SOCKET_EVENTS.SEARCH.QUERY, {
      ...data,
      _clientSocketId: socket.id,
    });
  });

  // ─── Disconnect ───
  socket.on('disconnect', (reason) => {
    console.log(`  🖥️  Admin disconnected: ${admin.email} (${reason})`);
  });
}

// ─── Relay Helpers ───

/**
 * Relay a message from client to a specific device.
 */
function relayToDevice(deviceId: string, event: string, data: any): boolean {
  const socketId = getDeviceSocketId(deviceId);

  if (!socketId) {
    // Device is offline — notify the client
    const clientSocketId = data._clientSocketId;
    if (clientSocketId) {
      const clientSocket = clientNamespace.sockets.get(clientSocketId);
      clientSocket?.emit(SOCKET_EVENTS.ERROR, {
        code: 'DEVICE_OFFLINE',
        message: 'Device is offline',
        deviceId,
      });
    }
    return false;
  }

  const deviceSocket = deviceNamespace.sockets.get(socketId);
  if (deviceSocket) {
    deviceSocket.emit(event, data);
    return true;
  }

  return false;
}

/**
 * Relay a message from device to a specific client.
 */
function relayToClient(clientSocketId: string, event: string, data: any): boolean {
  if (!clientSocketId) return false;

  const clientSocket = clientNamespace.sockets.get(clientSocketId);
  if (clientSocket) {
    // Remove internal relay metadata before sending to client
    const { _clientSocketId, ...cleanData } = data;
    clientSocket.emit(event, cleanData);
    return true;
  }

  return false;
}

/**
 * Get the Socket.IO server instance.
 */
export function getIO(): Server {
  return io;
}

/**
 * Get the device namespace.
 */
export function getDeviceNamespace(): Namespace {
  return deviceNamespace;
}

/**
 * Get the client namespace.
 */
export function getClientNamespace(): Namespace {
  return clientNamespace;
}

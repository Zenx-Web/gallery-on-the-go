/**
 * Client socket — singleton connection to the server's `/client` namespace
 * (server/src/modules/relay/relay.gateway.ts). Authenticated with the admin
 * JWT stored in localStorage on login (see app/page.tsx).
 */

import { io, Socket } from "socket.io-client";

const SERVER_URL =
  process.env.NEXT_PUBLIC_WS_URL ||
  process.env.NEXT_PUBLIC_API_URL ||
  "http://localhost:3001";

let socket: Socket | null = null;

export function getClientSocket(): Socket {
  if (socket) return socket;

  socket = io(`${SERVER_URL}/client`, {
    auth: { token: localStorage.getItem("token") },
    reconnection: true,
    reconnectionDelay: 3000,
    reconnectionDelayMax: 30000,
    reconnectionAttempts: Infinity,
    randomizationFactor: 0.3,
  });

  // Refresh auth token before each reconnect attempt in case it was rotated
  socket.on("reconnect_attempt", () => {
    socket!.auth = { token: localStorage.getItem("token") };
  });

  return socket;
}

export function disconnectClientSocket(): void {
  socket?.disconnect();
  socket = null;
}

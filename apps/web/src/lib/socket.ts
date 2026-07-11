/**
 * Client socket — singleton connection to the server's `/client` namespace
 * (server/src/modules/relay/relay.gateway.ts). Authenticated with the admin
 * JWT stored in localStorage on login (see app/page.tsx).
 */

import { io, Socket } from "socket.io-client";

const SERVER_URL =
  process.env.NEXT_PUBLIC_API_URL || "http://localhost:3001";

let socket: Socket | null = null;

export function getClientSocket(): Socket {
  if (socket) return socket;

  const token = localStorage.getItem("token");

  socket = io(`${SERVER_URL}/client`, {
    auth: { token },
    reconnection: true,
    reconnectionDelay: 5000,
    reconnectionAttempts: 10,
  });

  return socket;
}

export function disconnectClientSocket(): void {
  socket?.disconnect();
  socket = null;
}

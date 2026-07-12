/**
 * REST helper — thin fetch wrapper for the admin-authenticated device
 * endpoints (server/src/modules/device/device.routes.ts).
 */

import type { DeviceInfo } from "@gallery/shared";

const SERVER_URL =
  process.env.NEXT_PUBLIC_API_URL || "http://localhost:3001";

async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = localStorage.getItem("token");

  const res = await fetch(`${SERVER_URL}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });

  const body = await res.json();

  if (!res.ok || !body.success) {
    throw new Error(body.error || `Request failed (${res.status})`);
  }

  return body.data as T;
}

export function listDevices(): Promise<DeviceInfo[]> {
  return apiFetch<DeviceInfo[]>("/api/devices");
}

export function deleteDevice(id: string): Promise<void> {
  return apiFetch<void>(`/api/devices/${id}`, { method: "DELETE" });
}

export function wakeDevice(id: string): Promise<{ status: string }> {
  return apiFetch<{ status: string }>(`/api/devices/${id}/wake`, { method: "POST" });
}

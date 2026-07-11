"use client";

/**
 * DeviceContext — loads registered devices, tracks live status via the
 * `/client` socket's `device:status-change` event, and holds which device
 * is "active" for the Gallery/Downloads pages.
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";
import type { DeviceInfo } from "@gallery/shared";
import { SOCKET_EVENTS } from "@gallery/shared";
import { listDevices, deleteDevice } from "@/lib/api";
import { getClientSocket } from "@/lib/socket";

const SELECTED_DEVICE_KEY = "gallery.selected_device";

interface DeviceContextValue {
  devices: DeviceInfo[];
  loading: boolean;
  error: string | null;
  selectedDevice: DeviceInfo | null;
  selectDevice: (id: string) => void;
  refresh: () => Promise<void>;
  removeDevice: (id: string) => Promise<void>;
}

const DeviceContext = createContext<DeviceContextValue | null>(null);

export function DeviceProvider({ children }: { children: React.ReactNode }) {
  const [devices, setDevices] = useState<DeviceInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(() => {
    if (typeof window !== "undefined") {
      return localStorage.getItem(SELECTED_DEVICE_KEY);
    }
    return null;
  });

  const refresh = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const list = await listDevices();
      setDevices(list);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
  }, [refresh]);

  // Default selection: first online device, else first device — once devices load.
  useEffect(() => {
    if (devices.length === 0) return;
    const stillExists = devices.some((d) => d.id === selectedId);
    if (selectedId && stillExists) return;

    const fallback =
      devices.find((d) => d.status === "online") ?? devices[0] ?? null;
    if (fallback) {
      setTimeout(() => {
        setSelectedId(fallback.id);
        localStorage.setItem(SELECTED_DEVICE_KEY, fallback.id);
      }, 0);
    }
  }, [devices, selectedId]);

  useEffect(() => {
    const socket = getClientSocket();

    const onStatusChange = (data: { deviceId: string; status: DeviceInfo["status"] }) => {
      setDevices((prev) =>
        prev.map((d) => (d.id === data.deviceId ? { ...d, status: data.status } : d))
      );
    };

    socket.on(SOCKET_EVENTS.DEVICE.STATUS_CHANGE, onStatusChange);
    return () => {
      socket.off(SOCKET_EVENTS.DEVICE.STATUS_CHANGE, onStatusChange);
    };
  }, []);

  const selectDevice = useCallback((id: string) => {
    setSelectedId(id);
    localStorage.setItem(SELECTED_DEVICE_KEY, id);
  }, []);

  const removeDevice = useCallback(async (id: string) => {
    await deleteDevice(id);
    setDevices((prev) => prev.filter((d) => d.id !== id));
  }, []);

  const selectedDevice = useMemo(
    () => devices.find((d) => d.id === selectedId) ?? null,
    [devices, selectedId]
  );

  const value = useMemo(
    () => ({ devices, loading, error, selectedDevice, selectDevice, refresh, removeDevice }),
    [devices, loading, error, selectedDevice, selectDevice, refresh, removeDevice]
  );

  return <DeviceContext.Provider value={value}>{children}</DeviceContext.Provider>;
}

export function useDevices(): DeviceContextValue {
  const ctx = useContext(DeviceContext);
  if (!ctx) throw new Error("useDevices must be used within a DeviceProvider");
  return ctx;
}

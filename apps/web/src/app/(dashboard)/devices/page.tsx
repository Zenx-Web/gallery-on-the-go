"use client";

/**
 * Devices Page — Manage connected Android devices.
 */

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useRouter } from "next/navigation";
import TopBar from "@/components/TopBar";
import DeviceCard from "@/components/DeviceCard";
import EmptyState from "@/components/EmptyState";
import { useDevices } from "@/contexts/DeviceContext";
import { wakeDevice } from "@/lib/api";
import { Smartphone, RefreshCw, Trash2, Bell, HardDrive, CheckCircle, AlertCircle } from "lucide-react";

export default function DevicesPage() {
  const router = useRouter();
  const { devices, loading, selectedDevice, selectDevice, refresh, removeDevice } =
    useDevices();
  const [waking, setWaking] = useState(false);
  const [wakeResult, setWakeResult] = useState<{ ok: boolean; message: string } | null>(null);

  const handleRemove = async (id: string) => {
    if (!confirm("Remove this device? It will need to reconnect from the app to reappear.")) {
      return;
    }
    await removeDevice(id);
  };

  const handleWake = async () => {
    if (!selectedDevice || waking) return;
    setWaking(true);
    setWakeResult(null);
    try {
      const result = await wakeDevice(selectedDevice.id);
      const message =
        result.status === "already_online"
          ? "Device is already online."
          : result.status === "wake_sent"
          ? "Wake signal sent — device should reconnect shortly."
          : "Failed to send wake signal. Check the device FCM token.";
      setWakeResult({ ok: result.status !== "fcm_failed", message });
    } catch (err) {
      setWakeResult({ ok: false, message: (err as Error).message });
    } finally {
      setWaking(false);
      setTimeout(() => setWakeResult(null), 5000);
    }
  };

  return (
    <>
      <TopBar
        title="Devices"
        subtitle="Manage your connected Android devices"
        deviceName={selectedDevice?.deviceName}
        deviceStatus={selectedDevice?.status as "online" | "connecting" | "offline" | undefined}
      />

      <div className="p-4 sm:p-6 md:p-8 space-y-6">
        {/* Actions */}
        <div className="flex flex-wrap items-center gap-3">
          <button className="btn-primary" onClick={() => refresh()} disabled={loading}>
            <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
            Refresh
          </button>
          <button
            className="btn-ghost"
            onClick={handleWake}
            disabled={!selectedDevice || selectedDevice.status === "online" || waking}
            title={
              !selectedDevice
                ? "Select a device first"
                : selectedDevice.status === "online"
                ? "Device is already online"
                : "Send FCM push to wake the device"
            }
          >
            <Bell className={`w-4 h-4 ${waking ? "animate-pulse" : ""}`} />
            {waking ? "Waking…" : "Wake Device"}
          </button>
          <AnimatePresence>
            {wakeResult && (
              <motion.div
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -8 }}
                className={`flex items-center gap-1.5 text-xs px-3 py-1.5 rounded-lg ${
                  wakeResult.ok
                    ? "bg-green-500/10 text-green-400 border border-green-500/20"
                    : "bg-red-500/10 text-red-400 border border-red-500/20"
                }`}
              >
                {wakeResult.ok ? <CheckCircle className="w-3.5 h-3.5" /> : <AlertCircle className="w-3.5 h-3.5" />}
                {wakeResult.message}
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {devices.length === 0 && !loading ? (
          <EmptyState
            icon={Smartphone}
            title="No devices yet"
            description="Install the GalleryOnTheGo Android app on your phone and connect it to this server — it will show up here automatically."
          />
        ) : (
          <>
            {/* Device Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
              {devices.map((device, index) => (
                <motion.div
                  key={device.id}
                  initial={{ opacity: 0, y: 16 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: index * 0.08 }}
                >
                  <DeviceCard
                    id={device.id}
                    name={device.deviceName}
                    model={device.deviceModel}
                    status={device.status as "online" | "connecting" | "offline"}
                    lastSeen={device.lastSeenAt}
                    isSelected={selectedDevice?.id === device.id}
                    onSelect={selectDevice}
                  />
                </motion.div>
              ))}
            </div>

            {/* Selected Device Info */}
            {selectedDevice && (
              <motion.div
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                className="glass p-5 md:p-6"
              >
                <h3 className="text-sm font-semibold text-[var(--color-text-primary)] mb-4">
                  Selected Device Actions
                </h3>
                <div className="flex flex-wrap items-center gap-2.5">
                  <button className="btn-primary py-2 px-3.5 text-xs sm:text-sm" onClick={() => router.push("/gallery")}>
                    Browse Gallery
                  </button>
                  <button className="btn-ghost py-2 px-3.5 text-xs sm:text-sm" onClick={() => router.push("/downloads")}>
                    Browse Downloads
                  </button>
                  <button className="btn-ghost py-2 px-3.5 text-xs sm:text-sm flex items-center gap-1.5" onClick={() => router.push("/folders")}>
                    <HardDrive className="w-4 h-4" />
                    Browse Folders
                  </button>
                  <button
                    className="btn-ghost py-2 px-3.5 text-xs sm:text-sm text-red-400 border-red-500/20 hover:bg-red-500/10 hover:text-red-300 sm:ml-auto"
                    onClick={() => handleRemove(selectedDevice.id)}
                  >
                    <Trash2 className="w-4 h-4" />
                    Remove Device
                  </button>
                </div>
              </motion.div>
            )}
          </>
        )}
      </div>
    </>
  );
}

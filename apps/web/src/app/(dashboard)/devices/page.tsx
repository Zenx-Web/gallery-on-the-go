"use client";

/**
 * Devices Page — Manage connected Android devices.
 */

import { motion } from "framer-motion";
import { useRouter } from "next/navigation";
import TopBar from "@/components/TopBar";
import DeviceCard from "@/components/DeviceCard";
import EmptyState from "@/components/EmptyState";
import { useDevices } from "@/contexts/DeviceContext";
import { Smartphone, RefreshCw, Trash2, Bell } from "lucide-react";

export default function DevicesPage() {
  const router = useRouter();
  const { devices, loading, selectedDevice, selectDevice, refresh, removeDevice } =
    useDevices();

  const handleRemove = async (id: string) => {
    if (!confirm("Remove this device? It will need to reconnect from the app to reappear.")) {
      return;
    }
    await removeDevice(id);
  };

  return (
    <>
      <TopBar
        title="Devices"
        subtitle="Manage your connected Android devices"
        deviceName={selectedDevice?.deviceName}
        deviceStatus={selectedDevice?.status as "online" | "connecting" | "offline" | undefined}
      />

      <div className="p-8 space-y-6">
        {/* Actions */}
        <div className="flex items-center gap-3">
          <button className="btn-primary" onClick={() => refresh()} disabled={loading}>
            <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
            Refresh
          </button>
          <button
            className="btn-ghost opacity-50 cursor-not-allowed"
            disabled
            title="Push-notification wake isn't available yet"
          >
            <Bell className="w-4 h-4" />
            Wake Device
          </button>
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
                className="glass p-6"
              >
                <h3 className="text-sm font-semibold text-[var(--color-text-primary)] mb-4">
                  Selected Device Actions
                </h3>
                <div className="flex items-center gap-3">
                  <button className="btn-primary" onClick={() => router.push("/gallery")}>
                    Browse Gallery
                  </button>
                  <button className="btn-ghost" onClick={() => router.push("/downloads")}>
                    Browse Downloads
                  </button>
                  <button
                    className="btn-ghost text-red-400 border-red-500/20 hover:bg-red-500/10 hover:text-red-300 ml-auto"
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

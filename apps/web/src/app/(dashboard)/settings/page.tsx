"use client";

/**
 * Settings Page — Admin settings for theme, grid, and preferences.
 */

import { useState } from "react";
import { motion } from "framer-motion";
import TopBar from "@/components/TopBar";
import { useDevices } from "@/contexts/DeviceContext";
import {
  Palette,
  Grid3X3,
  RefreshCw,
  Bell,
  Shield,
  Save,
} from "lucide-react";

export default function SettingsPage() {
  const { selectedDevice } = useDevices();
  const [theme, setTheme] = useState("dark");
  const [gridColumns, setGridColumns] = useState(4);
  const [autoReconnect, setAutoReconnect] = useState(true);
  const [notifications, setNotifications] = useState(true);

  return (
    <>
      <TopBar
        title="Settings"
        subtitle="Configure your gallery preferences"
        deviceName={selectedDevice?.deviceName}
        deviceStatus={selectedDevice?.status as "online" | "connecting" | "offline" | undefined}
      />

      <div className="p-8 max-w-2xl space-y-6">
        {/* Appearance */}
        <motion.section
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0 }}
          className="glass p-6"
        >
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-purple-500/15 to-pink-500/10 flex items-center justify-center">
              <Palette className="w-4.5 h-4.5 text-purple-400" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-[var(--color-text-primary)]">
                Appearance
              </h3>
              <p className="text-xs text-[var(--color-text-tertiary)]">
                Customize the look and feel
              </p>
            </div>
          </div>

          <div className="space-y-4">
            {/* Theme */}
            <div className="flex items-center justify-between">
              <label className="text-sm text-[var(--color-text-secondary)]">
                Theme
              </label>
              <div className="flex gap-2">
                {["dark", "light"].map((t) => (
                  <button
                    key={t}
                    onClick={() => setTheme(t)}
                    className={`px-4 py-2 rounded-xl text-xs font-medium capitalize transition-all ${
                      theme === t
                        ? "bg-[var(--color-accent-primary)] text-white"
                        : "glass-sm text-[var(--color-text-secondary)]"
                    }`}
                  >
                    {t}
                  </button>
                ))}
              </div>
            </div>

            {/* Grid Columns */}
            <div className="flex items-center justify-between">
              <label className="text-sm text-[var(--color-text-secondary)]">
                Grid Columns
              </label>
              <div className="flex items-center gap-3">
                <input
                  type="range"
                  min={2}
                  max={8}
                  value={gridColumns}
                  onChange={(e) => setGridColumns(Number(e.target.value))}
                  className="w-32 accent-[var(--color-accent-primary)]"
                />
                <span className="text-sm font-mono text-[var(--color-text-secondary)] w-6 text-right">
                  {gridColumns}
                </span>
              </div>
            </div>
          </div>
        </motion.section>

        {/* Connection */}
        <motion.section
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.08 }}
          className="glass p-6"
        >
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-green-500/15 to-emerald-500/10 flex items-center justify-center">
              <RefreshCw className="w-4.5 h-4.5 text-green-400" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-[var(--color-text-primary)]">
                Connection
              </h3>
              <p className="text-xs text-[var(--color-text-tertiary)]">
                Device connection settings
              </p>
            </div>
          </div>

          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <label className="text-sm text-[var(--color-text-secondary)]">
                  Auto Reconnect
                </label>
                <p className="text-xs text-[var(--color-text-muted)] mt-0.5">
                  Automatically reconnect to devices
                </p>
              </div>
              <button
                onClick={() => setAutoReconnect(!autoReconnect)}
                className={`w-11 h-6 rounded-full transition-all relative ${
                  autoReconnect
                    ? "bg-[var(--color-accent-primary)]"
                    : "bg-[var(--color-surface-glass-active)]"
                }`}
              >
                <span
                  className={`absolute top-0.5 w-5 h-5 rounded-full bg-white transition-all ${
                    autoReconnect ? "left-[22px]" : "left-0.5"
                  }`}
                />
              </button>
            </div>

            <div className="flex items-center justify-between">
              <div>
                <label className="text-sm text-[var(--color-text-secondary)]">
                  Notifications
                </label>
                <p className="text-xs text-[var(--color-text-muted)] mt-0.5">
                  Device status change alerts
                </p>
              </div>
              <button
                onClick={() => setNotifications(!notifications)}
                className={`w-11 h-6 rounded-full transition-all relative ${
                  notifications
                    ? "bg-[var(--color-accent-primary)]"
                    : "bg-[var(--color-surface-glass-active)]"
                }`}
              >
                <span
                  className={`absolute top-0.5 w-5 h-5 rounded-full bg-white transition-all ${
                    notifications ? "left-[22px]" : "left-0.5"
                  }`}
                />
              </button>
            </div>
          </div>
        </motion.section>

        {/* Security */}
        <motion.section
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.16 }}
          className="glass p-6"
        >
          <div className="flex items-center gap-3 mb-5">
            <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-red-500/15 to-rose-500/10 flex items-center justify-center">
              <Shield className="w-4.5 h-4.5 text-red-400" />
            </div>
            <div>
              <h3 className="text-sm font-semibold text-[var(--color-text-primary)]">
                Security
              </h3>
              <p className="text-xs text-[var(--color-text-tertiary)]">
                Authentication & access control
              </p>
            </div>
          </div>

          <div className="space-y-3">
            <p className="text-sm text-[var(--color-text-secondary)]">
              Admin Email:{" "}
              <span className="font-mono text-[var(--color-text-primary)]">
                admin@galleryonthego.com
              </span>
            </p>
            <button className="btn-ghost text-sm">
              Change Password
            </button>
          </div>
        </motion.section>

        {/* Save */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.24 }}
        >
          <button className="btn-primary">
            <Save className="w-4 h-4" />
            Save Settings
          </button>
        </motion.div>
      </div>
    </>
  );
}

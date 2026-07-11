"use client";

/**
 * Dashboard Page — Overview with device status, quick stats, and recent photos.
 */

import { motion } from "framer-motion";
import TopBar from "@/components/TopBar";
import DeviceCard from "@/components/DeviceCard";
import EmptyState from "@/components/EmptyState";
import { useDevices } from "@/contexts/DeviceContext";
import {
  Images,
  FolderDown,
  Smartphone,
  Clock,
  ArrowRight,
  TrendingUp,
} from "lucide-react";
import Link from "next/link";

export default function DashboardPage() {
  const { devices, selectedDevice, selectDevice } = useDevices();
  const onlineCount = devices.filter((d) => d.status === "online").length;

  const stats = [
    {
      label: "Photos",
      value: "—",
      change: "Open Gallery to browse",
      icon: Images,
      color: "from-blue-500/15 to-cyan-500/10",
      textColor: "text-blue-400",
    },
    {
      label: "Downloads",
      value: "—",
      change: "Open Downloads to browse",
      icon: FolderDown,
      color: "from-amber-500/15 to-orange-500/10",
      textColor: "text-amber-400",
    },
    {
      label: "Devices",
      value: String(devices.length),
      change: `${onlineCount} online`,
      icon: Smartphone,
      color: "from-green-500/15 to-emerald-500/10",
      textColor: "text-green-400",
    },
    {
      label: "Status",
      value: selectedDevice ? selectedDevice.status : "—",
      change: selectedDevice ? selectedDevice.deviceName : "No device selected",
      icon: Clock,
      color: "from-purple-500/15 to-violet-500/10",
      textColor: "text-purple-400",
    },
  ];

  return (
    <>
      <TopBar
        title="Dashboard"
        subtitle="Overview of your connected devices"
        deviceName={selectedDevice?.deviceName}
        deviceStatus={selectedDevice?.status as "online" | "connecting" | "offline" | undefined}
      />

      <div className="p-8 space-y-8">
        {/* Stats Grid */}
        <section>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {stats.map((stat, index) => {
              const Icon = stat.icon;
              return (
                <motion.div
                  key={stat.label}
                  initial={{ opacity: 0, y: 16 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: index * 0.08 }}
                  className="glass p-5"
                >
                  <div className="flex items-start justify-between mb-3">
                    <div
                      className={`w-10 h-10 rounded-xl bg-gradient-to-br ${stat.color} flex items-center justify-center`}
                    >
                      <Icon className={`w-5 h-5 ${stat.textColor}`} />
                    </div>
                    <TrendingUp className="w-4 h-4 text-[var(--color-text-muted)]" />
                  </div>
                  <p className="text-2xl font-bold text-[var(--color-text-primary)] capitalize">
                    {stat.value}
                  </p>
                  <p className="text-xs text-[var(--color-text-tertiary)] mt-1">
                    {stat.change}
                  </p>
                </motion.div>
              );
            })}
          </div>
        </section>

        {/* Devices + Quick Access */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
          {/* Devices */}
          <section className="lg:col-span-1">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-[var(--color-text-primary)]">
                Connected Devices
              </h3>
              <Link
                href="/devices"
                className="text-xs text-[var(--color-accent-primary)] hover:underline flex items-center gap-1"
              >
                View all <ArrowRight className="w-3 h-3" />
              </Link>
            </div>
            {devices.length === 0 ? (
              <EmptyState
                icon={Smartphone}
                title="No devices yet"
                description="Connect the Android app to see it here."
              />
            ) : (
              <div className="space-y-3">
                {devices.map((device) => (
                  <DeviceCard
                    key={device.id}
                    id={device.id}
                    name={device.deviceName}
                    model={device.deviceModel}
                    status={device.status as "online" | "connecting" | "offline"}
                    lastSeen={device.lastSeenAt}
                    isSelected={selectedDevice?.id === device.id}
                    onSelect={selectDevice}
                  />
                ))}
              </div>
            )}
          </section>

          {/* Quick Access */}
          <section className="lg:col-span-2">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-[var(--color-text-primary)]">
                Quick Access
              </h3>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {[
                { label: "All Photos", icon: "🖼️", href: "/gallery" },
                { label: "Downloads", icon: "📥", href: "/downloads" },
                { label: "Devices", icon: "📱", href: "/devices" },
                { label: "Settings", icon: "⚙️", href: "/settings" },
              ].map((item, index) => (
                <motion.div
                  key={item.label}
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: 0.2 + index * 0.06 }}
                >
                  <Link
                    href={item.href}
                    className="glass p-4 flex items-center gap-3 hover:bg-[var(--color-surface-glass-hover)] hover:border-[var(--color-border-default)] transition-all block"
                  >
                    <span className="text-2xl">{item.icon}</span>
                    <p className="text-sm font-medium text-[var(--color-text-primary)]">
                      {item.label}
                    </p>
                  </Link>
                </motion.div>
              ))}
            </div>
          </section>
        </div>
      </div>
    </>
  );
}

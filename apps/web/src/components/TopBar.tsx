"use client";

/**
 * TopBar — Header bar with breadcrumb, device status, and actions.
 */

import { Smartphone, Wifi, WifiOff, Bell } from "lucide-react";

interface TopBarProps {
  title: string;
  subtitle?: string;
  deviceName?: string;
  deviceStatus?: "online" | "connecting" | "offline";
}

export default function TopBar({
  title,
  subtitle,
  deviceName,
  deviceStatus = "offline",
}: TopBarProps) {
  const statusConfig = {
    online: { label: "Online", color: "var(--color-status-online)", icon: Wifi },
    connecting: { label: "Connecting", color: "var(--color-status-connecting)", icon: Wifi },
    offline: { label: "Offline", color: "var(--color-status-offline)", icon: WifiOff },
  };

  const status = statusConfig[deviceStatus];
  const StatusIcon = status.icon;

  return (
    <header className="h-16 flex items-center justify-between px-8 border-b border-[var(--color-border-subtle)] bg-[rgba(10,10,15,0.6)] backdrop-blur-xl sticky top-0 z-30">
      {/* Left: Title */}
      <div>
        <h2 className="text-lg font-semibold text-[var(--color-text-primary)]">
          {title}
        </h2>
        {subtitle && (
          <p className="text-xs text-[var(--color-text-tertiary)]">{subtitle}</p>
        )}
      </div>

      {/* Right: Device Status + Actions */}
      <div className="flex items-center gap-4">
        {/* Device Status */}
        {deviceName && (
          <div className="glass-sm flex items-center gap-2.5 px-4 py-2 rounded-full">
            <Smartphone className="w-4 h-4 text-[var(--color-text-secondary)]" />
            <span className="text-sm font-medium text-[var(--color-text-secondary)]">
              {deviceName}
            </span>
            <div className="flex items-center gap-1.5">
              <span className={`status-dot ${deviceStatus}`} />
              <span
                className="text-xs font-medium"
                style={{ color: status.color }}
              >
                {status.label}
              </span>
            </div>
          </div>
        )}

        {/* Notifications */}
        <button className="w-9 h-9 rounded-xl flex items-center justify-center glass-sm hover:bg-[var(--color-surface-glass-hover)] transition-all">
          <Bell className="w-4 h-4 text-[var(--color-text-secondary)]" />
        </button>
      </div>
    </header>
  );
}

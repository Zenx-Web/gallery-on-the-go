"use client";

/**
 * TopBar — Header bar with breadcrumb, device status, and actions.
 */

import { Smartphone, Wifi, WifiOff, Bell, Menu } from "lucide-react";
import { useMobileNav } from "@/contexts/MobileNavContext";

interface TopBarProps {
  title: string;
  subtitle?: string;
  deviceName?: string;
  deviceStatus?: "online" | "connecting" | "offline";
  onMenuToggle?: () => void;
}

export default function TopBar({
  title,
  subtitle,
  deviceName,
  deviceStatus = "offline",
  onMenuToggle,
}: TopBarProps) {
  const { toggleMobileMenu } = useMobileNav();
  const handleToggle = onMenuToggle || toggleMobileMenu;

  const statusConfig = {
    online: { label: "Online", color: "var(--color-status-online)", icon: Wifi },
    connecting: { label: "Connecting", color: "var(--color-status-connecting)", icon: Wifi },
    offline: { label: "Offline", color: "var(--color-status-offline)", icon: WifiOff },
  };

  const status = statusConfig[deviceStatus];

  return (
    <header className="h-16 flex items-center justify-between px-4 md:px-8 border-b border-[var(--color-border-subtle)] bg-[rgba(10,10,15,0.75)] backdrop-blur-xl sticky top-0 z-30">
      {/* Left: Mobile Menu Button + Title */}
      <div className="flex items-center gap-3">
        <button
          onClick={handleToggle}
          className="md:hidden p-2 rounded-xl glass-sm hover:bg-[var(--color-surface-glass-hover)] text-[var(--color-text-secondary)] min-w-[44px] min-h-[44px] flex items-center justify-center"
          aria-label="Open menu"
        >
          <Menu className="w-5 h-5" />
        </button>

        <div>
          <h2 className="text-base md:text-lg font-semibold text-[var(--color-text-primary)] truncate max-w-[180px] sm:max-w-none">
            {title}
          </h2>
          {subtitle && (
            <p className="text-[11px] md:text-xs text-[var(--color-text-tertiary)] truncate max-w-[200px] sm:max-w-none">
              {subtitle}
            </p>
          )}
        </div>
      </div>

      {/* Right: Device Status + Actions */}
      <div className="flex items-center gap-2 md:gap-4">
        {/* Device Status */}
        {deviceName && (
          <div className="glass-sm flex items-center gap-2 px-2.5 py-1.5 md:px-4 md:py-2 rounded-full">
            <Smartphone className="w-3.5 h-3.5 md:w-4 md:h-4 text-[var(--color-text-secondary)]" />
            <span className="text-xs md:text-sm font-medium text-[var(--color-text-secondary)] max-w-[80px] sm:max-w-[140px] truncate">
              {deviceName}
            </span>
            <div className="flex items-center gap-1.5">
              <span className={`status-dot ${deviceStatus}`} />
              <span
                className="hidden sm:inline text-xs font-medium"
                style={{ color: status.color }}
              >
                {status.label}
              </span>
            </div>
          </div>
        )}

        {/* Notifications */}
        <button
          aria-label="Notifications"
          className="w-9 h-9 rounded-xl flex items-center justify-center glass-sm hover:bg-[var(--color-surface-glass-hover)] transition-all min-w-[36px] min-h-[36px]"
        >
          <Bell className="w-4 h-4 text-[var(--color-text-secondary)]" />
        </button>
      </div>
    </header>
  );
}

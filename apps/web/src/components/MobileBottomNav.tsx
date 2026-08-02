"use client";

/**
 * MobileBottomNav — Fixed bottom navigation bar for mobile devices (< 768px).
 * Glassmorphic design with active indicators and touch-friendly targets.
 */

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Images,
  FolderDown,
  HardDrive,
  Smartphone,
  Settings,
} from "lucide-react";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/gallery", label: "Gallery", icon: Images },
  { href: "/folders", label: "Folders", icon: HardDrive },
  { href: "/downloads", label: "Downloads", icon: FolderDown },
  { href: "/devices", label: "Devices", icon: Smartphone },
  { href: "/settings", label: "Settings", icon: Settings },
];

export default function MobileBottomNav() {
  const pathname = usePathname();

  return (
    <nav className="md:hidden fixed bottom-0 left-0 right-0 z-40 bg-[rgba(10,10,15,0.85)] backdrop-blur-xl border-t border-[var(--color-border-subtle)] px-2 py-1.5 pb-[max(0.375rem,env(safe-area-inset-bottom))] shadow-2xl">
      <div className="flex items-center justify-around">
        {navItems.map((item) => {
          const isActive =
            pathname === item.href || pathname?.startsWith(item.href + "/");
          const Icon = item.icon;

          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex flex-col items-center justify-center py-1 px-2 rounded-xl transition-all duration-200 min-w-[56px] min-h-[44px] ${
                isActive
                  ? "text-[var(--color-accent-primary)] font-semibold bg-[rgba(108,99,255,0.12)]"
                  : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)]"
              }`}
            >
              <Icon className={`w-5 h-5 mb-0.5 ${isActive ? "scale-110" : ""}`} />
              <span className="text-[10px] leading-tight tracking-tight">
                {item.label}
              </span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}

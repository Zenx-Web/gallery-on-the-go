"use client";

/**
 * Sidebar — Main navigation for the gallery app.
 * Glassmorphism sidebar with animated active states.
 */

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { disconnectClientSocket } from "@/lib/socket";
import {
  Images,
  FolderDown,
  LayoutDashboard,
  Settings,
  Smartphone,
  Search,
  LogOut,
  Aperture,
} from "lucide-react";

const navItems = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/gallery", label: "Gallery", icon: Images },
  { href: "/downloads", label: "Downloads", icon: FolderDown },
  { href: "/devices", label: "Devices", icon: Smartphone },
  { href: "/settings", label: "Settings", icon: Settings },
];

export default function Sidebar() {
  const pathname = usePathname();
  const router = useRouter();

  const handleLogout = () => {
    localStorage.removeItem("token");
    localStorage.removeItem("gallery.selected_device");
    disconnectClientSocket();
    router.push("/");
  };

  return (
    <aside className="sidebar">
      {/* Logo */}
      <div className="px-6 py-6 flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[var(--color-accent-primary)] to-[var(--color-accent-secondary)] flex items-center justify-center shadow-lg">
          <Aperture className="w-5 h-5 text-white" />
        </div>
        <div>
          <h1 className="text-base font-bold text-[var(--color-text-primary)] tracking-tight">
            Gallery<span className="text-gradient">OnTheGo</span>
          </h1>
          <p className="text-[10px] text-[var(--color-text-tertiary)] font-medium uppercase tracking-widest">
            Remote Access
          </p>
        </div>
      </div>

      {/* Search */}
      <div className="px-4 mb-2">
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-tertiary)]" />
          <input
            type="text"
            placeholder="Search files..."
            className="input-glass w-full pl-9 py-2.5 text-sm rounded-xl"
          />
        </div>
      </div>

      {/* Navigation */}
      <nav className="flex-1 py-4 space-y-1">
        <p className="px-6 mb-2 text-[11px] font-semibold text-[var(--color-text-muted)] uppercase tracking-wider">
          Navigate
        </p>
        {navItems.map((item) => {
          const isActive =
            pathname === item.href || pathname?.startsWith(item.href + "/");
          const Icon = item.icon;

          return (
            <Link
              key={item.href}
              href={item.href}
              className={`sidebar-link ${isActive ? "active" : ""}`}
            >
              <Icon className="w-[18px] h-[18px]" />
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="p-4 border-t border-[var(--color-border-subtle)]">
        <button
          onClick={handleLogout}
          className="sidebar-link w-full text-[var(--color-text-tertiary)] hover:text-red-400"
        >
          <LogOut className="w-[18px] h-[18px]" />
          <span>Logout</span>
        </button>
      </div>
    </aside>
  );
}

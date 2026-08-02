"use client";

/**
 * Dashboard Layout — Wraps all authenticated pages.
 * Contains the sidebar + main content area.
 */

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Sidebar from "@/components/Sidebar";
import MobileBottomNav from "@/components/MobileBottomNav";
import { DeviceProvider } from "@/contexts/DeviceContext";
import { MobileNavProvider, useMobileNav } from "@/contexts/MobileNavContext";
import { disconnectClientSocket } from "@/lib/socket";

function DashboardContent({ children }: { children: React.ReactNode }) {
  const { isMobileMenuOpen, closeMobileMenu } = useMobileNav();

  return (
    <div className="flex min-h-screen flex-col md:flex-row">
      <Sidebar isOpen={isMobileMenuOpen} onClose={closeMobileMenu} />
      <main className="flex-1 md:ml-[260px] ml-0 min-h-screen overflow-x-hidden pb-20 md:pb-0">
        {children}
      </main>
      <MobileBottomNav />
    </div>
  );
}

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const router = useRouter();
  const [authenticated, setAuthenticated] = useState(false);

  useEffect(() => {
    const token = localStorage.getItem("token");
    if (!token) {
      // In development, allow access without token for UI preview
      if (process.env.NODE_ENV === "development") {
        setTimeout(() => setAuthenticated(true), 0);
        return;
      }
      disconnectClientSocket();
      router.push("/");
      return;
    }

    // Verify token
    fetch(
      `${process.env.NEXT_PUBLIC_API_URL || "http://localhost:3001"}/api/auth/verify`,
      {
        headers: { Authorization: `Bearer ${token}` },
      }
    )
      .then((res) => {
        if (!res.ok) {
          localStorage.removeItem("token");
          disconnectClientSocket();
          router.push("/");
        } else {
          setAuthenticated(true);
        }
      })
      .catch(() => {
        // In development, allow even if server is down
        setAuthenticated(true);
      });
  }, [router]);

  if (!authenticated) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-[var(--color-accent-primary)] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <DeviceProvider>
      <MobileNavProvider>
        <DashboardContent>{children}</DashboardContent>
      </MobileNavProvider>
    </DeviceProvider>
  );
}

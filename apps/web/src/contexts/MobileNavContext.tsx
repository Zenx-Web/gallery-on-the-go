"use client";

/**
 * MobileNavContext — Global context for controlling the mobile navigation drawer.
 */

import React, { createContext, useContext, useState } from "react";

interface MobileNavContextType {
  isMobileMenuOpen: boolean;
  openMobileMenu: () => void;
  closeMobileMenu: () => void;
  toggleMobileMenu: () => void;
}

const MobileNavContext = createContext<MobileNavContextType>({
  isMobileMenuOpen: false,
  openMobileMenu: () => {},
  closeMobileMenu: () => {},
  toggleMobileMenu: () => {},
});

export const MobileNavProvider = ({
  children,
}: {
  children: React.ReactNode;
}) => {
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  return (
    <MobileNavContext.Provider
      value={{
        isMobileMenuOpen,
        openMobileMenu: () => setIsMobileMenuOpen(true),
        closeMobileMenu: () => setIsMobileMenuOpen(false),
        toggleMobileMenu: () => setIsMobileMenuOpen((prev) => !prev),
      }}
    >
      {children}
    </MobileNavContext.Provider>
  );
};

export const useMobileNav = () => useContext(MobileNavContext);

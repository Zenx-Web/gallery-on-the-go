import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  weight: ["300", "400", "500", "600", "700", "800"],
});

export const metadata: Metadata = {
  title: "GalleryOnTheGo — Remote Gallery",
  description:
    "Access your Android phone's photos and downloads from anywhere. Secure, private, no cloud uploads.",
  keywords: ["gallery", "remote", "android", "photos", "privacy"],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${inter.variable} h-full`}>
      <body className="min-h-full">
        <div className="bg-gradient-animated" />
        {children}
      </body>
    </html>
  );
}

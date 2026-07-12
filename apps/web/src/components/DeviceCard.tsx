"use client";

/**
 * DeviceCard — Shows a connected Android device with status and selection.
 * Offline devices show a "Wake" button that sends an FCM reconnect signal.
 */

import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { Smartphone, Check, RefreshCw, CheckCircle2, AlertCircle } from "lucide-react";
import { wakeDevice } from "@/lib/api";

interface DeviceCardProps {
  id: string;
  name: string;
  model: string | null;
  status: "online" | "connecting" | "offline";
  lastSeen: string | null;
  isSelected?: boolean;
  onSelect: (id: string) => void;
}

type WakeState = "idle" | "sending" | "sent" | "failed";

export default function DeviceCard({
  id,
  name,
  model,
  status,
  lastSeen,
  isSelected = false,
  onSelect,
}: DeviceCardProps) {
  const [wakeState, setWakeState] = useState<WakeState>("idle");

  const statusLabels = {
    online: "Online",
    connecting: "Connecting...",
    offline: "Offline",
  };

  async function handleWake(e: React.MouseEvent) {
    e.stopPropagation(); // don't select the card
    if (wakeState === "sending") return;

    setWakeState("sending");
    try {
      await wakeDevice(id);
      setWakeState("sent");
    } catch {
      setWakeState("failed");
    }
    // Reset after 3 s so the button is usable again
    setTimeout(() => setWakeState("idle"), 3000);
  }

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      whileHover={{ y: -2 }}
      onClick={() => onSelect(id)}
      className={`glass p-5 cursor-pointer transition-all duration-300 ${
        isSelected
          ? "ring-2 ring-[var(--color-accent-primary)] glow-accent"
          : "hover:border-[var(--color-border-strong)]"
      }`}
    >
      <div className="flex items-start gap-4">
        {/* Phone Icon */}
        <div
          className={`w-12 h-12 rounded-xl flex items-center justify-center ${
            status === "online"
              ? "bg-gradient-to-br from-green-500/20 to-emerald-500/10"
              : status === "connecting"
              ? "bg-gradient-to-br from-yellow-500/20 to-amber-500/10"
              : "bg-gradient-to-br from-gray-500/20 to-gray-600/10"
          }`}
        >
          <Smartphone
            className={`w-5 h-5 ${
              status === "online"
                ? "text-green-400"
                : status === "connecting"
                ? "text-yellow-400"
                : "text-gray-500"
            }`}
          />
        </div>

        {/* Info */}
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-semibold text-[var(--color-text-primary)] truncate">
              {name}
            </h3>
            {isSelected && (
              <div className="w-5 h-5 rounded-full bg-[var(--color-accent-primary)] flex items-center justify-center">
                <Check className="w-3 h-3 text-white" />
              </div>
            )}
          </div>
          {model && (
            <p className="text-xs text-[var(--color-text-tertiary)] mt-0.5 truncate">
              {model}
            </p>
          )}
          <div className="flex items-center justify-between mt-2">
            <div className="flex items-center gap-1.5">
              <span className={`status-dot ${status}`} />
              <span className="text-xs font-medium text-[var(--color-text-secondary)]">
                {statusLabels[status]}
              </span>
            </div>

            {/* Wake button — only shown when offline */}
            {status === "offline" && (
              <AnimatePresence mode="wait">
                <motion.button
                  key={wakeState}
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.8 }}
                  transition={{ duration: 0.15 }}
                  onClick={handleWake}
                  disabled={wakeState === "sending"}
                  title="Send wake signal — device will reconnect automatically"
                  className={`flex items-center gap-1 px-2 py-0.5 rounded-md text-[10px] font-medium transition-colors ${
                    wakeState === "sent"
                      ? "bg-green-500/20 text-green-400 border border-green-500/30"
                      : wakeState === "failed"
                      ? "bg-red-500/20 text-red-400 border border-red-500/30"
                      : "bg-[var(--color-accent-primary)]/10 text-[var(--color-accent-primary)] border border-[var(--color-accent-primary)]/30 hover:bg-[var(--color-accent-primary)]/20"
                  }`}
                >
                  {wakeState === "sending" && (
                    <RefreshCw className="w-3 h-3 animate-spin" />
                  )}
                  {wakeState === "sent" && (
                    <CheckCircle2 className="w-3 h-3" />
                  )}
                  {wakeState === "failed" && (
                    <AlertCircle className="w-3 h-3" />
                  )}
                  {wakeState === "idle" && (
                    <RefreshCw className="w-3 h-3" />
                  )}
                  {wakeState === "idle" && "Wake"}
                  {wakeState === "sending" && "Sending…"}
                  {wakeState === "sent" && "Signal sent"}
                  {wakeState === "failed" && "Failed"}
                </motion.button>
              </AnimatePresence>
            )}
          </div>

          {lastSeen && status === "offline" && (
            <p className="text-[10px] text-[var(--color-text-muted)] mt-1">
              Last seen {new Date(lastSeen).toLocaleDateString()}
            </p>
          )}
        </div>
      </div>
    </motion.div>
  );
}

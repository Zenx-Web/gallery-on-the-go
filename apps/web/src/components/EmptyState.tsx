"use client";

/**
 * EmptyState — Shown when no content is available.
 * Animated illustration with message and optional action.
 */

import { motion } from "framer-motion";
import { LucideIcon } from "lucide-react";

interface EmptyStateProps {
  icon: LucideIcon;
  title: string;
  description: string;
  action?: {
    label: string;
    onClick: () => void;
  };
}

export default function EmptyState({
  icon: Icon,
  title,
  description,
  action,
}: EmptyStateProps) {
  return (
    <motion.div
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      className="flex flex-col items-center justify-center py-20 px-8"
    >
      <div className="w-20 h-20 rounded-2xl bg-gradient-to-br from-[var(--color-accent-primary)]/10 to-[var(--color-accent-secondary)]/5 flex items-center justify-center mb-6">
        <Icon className="w-8 h-8 text-[var(--color-accent-primary)]" />
      </div>
      <h3 className="text-lg font-semibold text-[var(--color-text-primary)] mb-2">
        {title}
      </h3>
      <p className="text-sm text-[var(--color-text-tertiary)] text-center max-w-sm">
        {description}
      </p>
      {action && (
        <button onClick={action.onClick} className="btn-primary mt-6">
          {action.label}
        </button>
      )}
    </motion.div>
  );
}

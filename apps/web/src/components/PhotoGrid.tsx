"use client";

/**
 * PhotoGrid — Responsive masonry-style photo grid with hover overlays.
 * Supports selection, lazy loading, and animated entrance.
 */

import { motion } from "framer-motion";
import { Download, Eye, Check } from "lucide-react";
import { useState } from "react";

export interface PhotoItem {
  id: string;
  name: string;
  thumbnailUrl: string;
  mimeType: string;
  size: number;
  width?: number;
  height?: number;
  createdAt: string;
}

interface PhotoGridProps {
  photos: PhotoItem[];
  onPhotoClick: (photo: PhotoItem) => void;
  onDownload?: (photo: PhotoItem) => void;
  selectable?: boolean;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

export default function PhotoGrid({
  photos,
  onPhotoClick,
  onDownload,
  selectable = false,
}: PhotoGridProps) {
  const [selected, setSelected] = useState<Set<string>>(new Set());

  const toggleSelect = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  return (
    <div className="gallery-grid">
      {photos.map((photo, index) => {
        const isSelected = selected.has(photo.id);

        return (
          <motion.div
            key={photo.id}
            initial={{ opacity: 0, scale: 0.92 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{
              delay: Math.min(index * 0.03, 0.6),
              duration: 0.35,
              ease: "easeOut",
            }}
            className={`gallery-item ${
              isSelected ? "ring-2 ring-[var(--color-accent-primary)] ring-offset-2 ring-offset-[var(--color-bg-primary)]" : ""
            }`}
            onClick={() =>
              selectable ? toggleSelect(photo.id) : onPhotoClick(photo)
            }
          >
            {photo.thumbnailUrl ? (
              <img
                src={photo.thumbnailUrl}
                alt={photo.name}
                loading="lazy"
                className="w-full h-full object-cover"
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center bg-[var(--color-surface-glass)]">
                <div className="w-5 h-5 border-2 border-[var(--color-accent-primary)] border-t-transparent rounded-full animate-spin" />
              </div>
            )}

            {/* Hover Overlay */}
            <div className="overlay">
              <div className="flex items-center justify-between w-full">
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-medium text-white truncate">
                    {photo.name}
                  </p>
                  <p className="text-[10px] text-white/60">
                    {formatSize(photo.size)}
                  </p>
                </div>
                <div className="flex items-center gap-1 ml-2">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      onPhotoClick(photo);
                    }}
                    className="w-7 h-7 rounded-lg bg-white/10 hover:bg-white/20 flex items-center justify-center transition-all"
                  >
                    <Eye className="w-3.5 h-3.5 text-white" />
                  </button>
                  {onDownload && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        onDownload(photo);
                      }}
                      className="w-7 h-7 rounded-lg bg-white/10 hover:bg-white/20 flex items-center justify-center transition-all"
                    >
                      <Download className="w-3.5 h-3.5 text-white" />
                    </button>
                  )}
                </div>
              </div>
            </div>

            {/* Selection Checkbox */}
            {selectable && (
              <div className="absolute top-2 left-2">
                <div
                  className={`w-6 h-6 rounded-md flex items-center justify-center transition-all ${
                    isSelected
                      ? "bg-[var(--color-accent-primary)] border-[var(--color-accent-primary)]"
                      : "bg-black/30 border border-white/30 backdrop-blur-sm"
                  }`}
                >
                  {isSelected && <Check className="w-3.5 h-3.5 text-white" />}
                </div>
              </div>
            )}

            {/* Video Duration Badge */}
            {photo.mimeType.startsWith("video/") && (
              <div className="absolute top-2 right-2 px-1.5 py-0.5 rounded bg-black/60 backdrop-blur-sm text-[10px] font-medium text-white">
                VIDEO
              </div>
            )}
          </motion.div>
        );
      })}
    </div>
  );
}

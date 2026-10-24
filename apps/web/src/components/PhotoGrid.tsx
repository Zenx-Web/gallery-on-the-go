"use client";

/**
 * PhotoGrid — Responsive masonry-style photo grid with hover overlays.
 * Supports selection, lazy loading, and animated entrance.
 *
 * Selection can be controlled by the parent via `selectedIds` +
 * `onSelectionChange`, or managed internally when only `selectable` is set.
 */

import { motion } from "framer-motion";
import { Download, Eye, Check } from "lucide-react";
import { useCallback, useState } from "react";

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
  /** Parent-controlled selection set. When provided, internal state is bypassed. */
  selectedIds?: Set<string>;
  /** Called when a photo's selection is toggled (parent-controlled mode). */
  onSelectionChange?: (selectedIds: Set<string>) => void;
  /** "comfortable" (default) renders fewer, larger tiles than "compact". */
  size?: "compact" | "comfortable";
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
  selectedIds: externalSelected,
  onSelectionChange,
  size = "comfortable",
}: PhotoGridProps) {
  // Fallback internal state for when the parent doesn't control selection.
  const [internalSelected, setInternalSelected] = useState<Set<string>>(new Set());

  const selected = externalSelected ?? internalSelected;

  const toggleSelect = useCallback(
    (id: string) => {
      const next = new Set(selected);
      if (next.has(id)) next.delete(id);
      else next.add(id);

      if (onSelectionChange) {
        onSelectionChange(next);
      } else {
        setInternalSelected(next);
      }
    },
    [selected, onSelectionChange]
  );

  return (
    <div
      className={`gallery-grid${
        size === "comfortable" ? " gallery-grid--comfortable" : ""
      }`}
    >
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
            className={`gallery-item group relative ${
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
                onError={() =>
                  console.warn(
                    `Thumbnail image failed to decode for ${photo.name} (${photo.id}): ${photo.thumbnailUrl}`
                  )
                }
              />
            ) : (
              <div className="w-full h-full flex items-center justify-center bg-[var(--color-surface-glass)]">
                <div className="w-5 h-5 border-2 border-[var(--color-accent-primary)] border-t-transparent rounded-full animate-spin" />
              </div>
            )}

            {/* Hover Overlay — hidden in select mode so the checkbox is the primary affordance */}
            {!selectable && (
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
            )}

            {/* Selection Checkbox — always visible in select mode OR visible on hover in normal mode */}
            <div
              className={`absolute top-2 left-2 z-20 transition-all duration-150 ${
                selectable || isSelected
                  ? "opacity-100 scale-100 pointer-events-auto"
                  : "opacity-0 group-hover:opacity-100 scale-95 group-hover:scale-100 pointer-events-none group-hover:pointer-events-auto"
              }`}
              onClick={(e) => {
                e.stopPropagation();
                toggleSelect(photo.id);
              }}
            >
              <div
                className={`w-6 h-6 rounded-md flex items-center justify-center transition-all shadow-md cursor-pointer ${
                  isSelected
                    ? "bg-[var(--color-accent-primary)] border-2 border-[var(--color-accent-primary)]"
                    : "bg-black/50 hover:bg-black/70 border-2 border-white/60 hover:border-white backdrop-blur-sm"
                }`}
                title={isSelected ? "Deselect" : "Select photo"}
              >
                {isSelected && <Check className="w-3.5 h-3.5 text-white" />}
              </div>
            </div>

            {/* File name badge in select mode (bottom overlay) */}
            {selectable && (
              <div className="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/60 to-transparent px-2 pb-1.5 pt-4">
                <p className="text-[10px] font-medium text-white/80 truncate">
                  {photo.name}
                </p>
              </div>
            )}

            {/* Video Duration Badge */}
            {photo.mimeType.startsWith("video/") && (
              <div className={`absolute ${selectable ? "top-2 left-10" : "top-2 right-2"} px-1.5 py-0.5 rounded bg-black/60 backdrop-blur-sm text-[10px] font-medium text-white`}>
                VIDEO
              </div>
            )}
          </motion.div>
        );
      })}
    </div>
  );
}

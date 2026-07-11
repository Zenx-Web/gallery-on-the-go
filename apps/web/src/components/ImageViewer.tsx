"use client";

/**
 * ImageViewer — Fullscreen lightbox for viewing images.
 * Features: zoom, download, navigation, glassmorphism controls.
 */

import { motion, AnimatePresence } from "framer-motion";
import {
  X,
  Download,
  ChevronLeft,
  ChevronRight,
  ZoomIn,
  ZoomOut,
  Info,
} from "lucide-react";
import { useState, useCallback, useEffect } from "react";

interface ImageViewerProps {
  isOpen: boolean;
  imageUrl: string;
  imageName: string;
  imageSize?: number;
  imageDate?: string;
  onClose: () => void;
  onDownload?: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  hasPrev?: boolean;
  hasNext?: boolean;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1048576).toFixed(1)} MB`;
}

export default function ImageViewer({
  isOpen,
  imageUrl,
  imageName,
  imageSize,
  imageDate,
  onClose,
  onDownload,
  onPrev,
  onNext,
  hasPrev = false,
  hasNext = false,
}: ImageViewerProps) {
  const [zoom, setZoom] = useState(1);
  const [showInfo, setShowInfo] = useState(false);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      switch (e.key) {
        case "Escape":
          onClose();
          break;
        case "ArrowLeft":
          if (hasPrev && onPrev) onPrev();
          break;
        case "ArrowRight":
          if (hasNext && onNext) onNext();
          break;
        case "+":
        case "=":
          setZoom((z) => Math.min(z + 0.25, 4));
          break;
        case "-":
          setZoom((z) => Math.max(z - 0.25, 0.5));
          break;
      }
    },
    [onClose, onPrev, onNext, hasPrev, hasNext]
  );

  useEffect(() => {
    if (isOpen) {
      window.addEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "hidden";
    }
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = "";
    };
  }, [isOpen, handleKeyDown]);

  // Reset zoom on image change
  useEffect(() => {
    setZoom(1);
  }, [imageUrl]);

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.2 }}
          className="lightbox-backdrop"
          onClick={onClose}
        >
          {/* Top Controls */}
          <motion.div
            initial={{ y: -20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            className="absolute top-0 left-0 right-0 h-16 flex items-center justify-between px-6 bg-gradient-to-b from-black/60 to-transparent z-10"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium text-white truncate">
                {imageName}
              </p>
              {imageSize && (
                <p className="text-xs text-white/50">{formatSize(imageSize)}</p>
              )}
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => setZoom((z) => Math.max(z - 0.25, 0.5))}
                className="w-9 h-9 rounded-xl glass-sm flex items-center justify-center hover:bg-white/10 transition-all"
              >
                <ZoomOut className="w-4 h-4 text-white" />
              </button>
              <span className="text-xs text-white/60 font-mono w-12 text-center">
                {Math.round(zoom * 100)}%
              </span>
              <button
                onClick={() => setZoom((z) => Math.min(z + 0.25, 4))}
                className="w-9 h-9 rounded-xl glass-sm flex items-center justify-center hover:bg-white/10 transition-all"
              >
                <ZoomIn className="w-4 h-4 text-white" />
              </button>
              <button
                onClick={() => setShowInfo(!showInfo)}
                className="w-9 h-9 rounded-xl glass-sm flex items-center justify-center hover:bg-white/10 transition-all"
              >
                <Info className="w-4 h-4 text-white" />
              </button>
              {onDownload && (
                <button
                  onClick={onDownload}
                  className="btn-primary py-2 px-4 text-xs"
                >
                  <Download className="w-3.5 h-3.5" />
                  Download
                </button>
              )}
              <button
                onClick={onClose}
                className="w-9 h-9 rounded-xl glass-sm flex items-center justify-center hover:bg-red-500/20 transition-all"
              >
                <X className="w-4 h-4 text-white" />
              </button>
            </div>
          </motion.div>

          {/* Image */}
          <motion.div
            initial={{ scale: 0.9, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            exit={{ scale: 0.9, opacity: 0 }}
            transition={{ duration: 0.25, ease: "easeOut" }}
            className="max-w-[90vw] max-h-[85vh] overflow-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <img
              src={imageUrl}
              alt={imageName}
              style={{ transform: `scale(${zoom})`, transformOrigin: "center" }}
              className="max-w-full max-h-[85vh] object-contain transition-transform duration-200 rounded-lg select-none"
              draggable={false}
            />
          </motion.div>

          {/* Navigation Arrows */}
          {hasPrev && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onPrev?.();
              }}
              className="absolute left-4 top-1/2 -translate-y-1/2 w-12 h-12 rounded-2xl glass-sm flex items-center justify-center hover:bg-white/10 transition-all z-10"
            >
              <ChevronLeft className="w-6 h-6 text-white" />
            </button>
          )}
          {hasNext && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onNext?.();
              }}
              className="absolute right-4 top-1/2 -translate-y-1/2 w-12 h-12 rounded-2xl glass-sm flex items-center justify-center hover:bg-white/10 transition-all z-10"
            >
              <ChevronRight className="w-6 h-6 text-white" />
            </button>
          )}

          {/* Info Panel */}
          <AnimatePresence>
            {showInfo && (
              <motion.div
                initial={{ x: 300, opacity: 0 }}
                animate={{ x: 0, opacity: 1 }}
                exit={{ x: 300, opacity: 0 }}
                transition={{ duration: 0.25 }}
                className="absolute right-0 top-16 bottom-0 w-72 glass-strong p-6 overflow-y-auto z-10"
                onClick={(e) => e.stopPropagation()}
              >
                <h3 className="text-sm font-semibold text-white mb-4">
                  File Details
                </h3>
                <div className="space-y-3">
                  <div>
                    <p className="text-[11px] text-white/40 uppercase tracking-wider">
                      Name
                    </p>
                    <p className="text-sm text-white/80 break-all">
                      {imageName}
                    </p>
                  </div>
                  {imageSize && (
                    <div>
                      <p className="text-[11px] text-white/40 uppercase tracking-wider">
                        Size
                      </p>
                      <p className="text-sm text-white/80">
                        {formatSize(imageSize)}
                      </p>
                    </div>
                  )}
                  {imageDate && (
                    <div>
                      <p className="text-[11px] text-white/40 uppercase tracking-wider">
                        Date
                      </p>
                      <p className="text-sm text-white/80">
                        {new Date(imageDate).toLocaleDateString("en-US", {
                          year: "numeric",
                          month: "long",
                          day: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </p>
                    </div>
                  )}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </motion.div>
      )}
    </AnimatePresence>
  );
}

"use client";

/**
 * FolderGrid — Displays album/folder cards in a responsive grid.
 * Each folder shows a cover thumbnail, name, and file count.
 */

import { Folder, Image, Camera, MessageCircle, Download, Film, Music } from "lucide-react";
import { motion } from "framer-motion";

export interface FolderItem {
  id: string;
  name: string;
  fileCount: number;
  coverUrl?: string;
  type?: "camera" | "screenshots" | "whatsapp" | "downloads" | "videos" | "music" | "other";
}

interface FolderGridProps {
  folders: FolderItem[];
  onFolderClick: (folder: FolderItem) => void;
  onDownloadZip?: (folder: FolderItem) => void;
}

const folderIcons: Record<string, typeof Folder> = {
  camera: Camera,
  screenshots: Image,
  whatsapp: MessageCircle,
  downloads: Download,
  videos: Film,
  music: Music,
  other: Folder,
};

const folderColors: Record<string, string> = {
  camera: "from-blue-500/20 to-cyan-500/10",
  screenshots: "from-purple-500/20 to-pink-500/10",
  whatsapp: "from-green-500/20 to-emerald-500/10",
  downloads: "from-amber-500/20 to-orange-500/10",
  videos: "from-red-500/20 to-rose-500/10",
  music: "from-indigo-500/20 to-violet-500/10",
  other: "from-[var(--color-accent-primary)]/15 to-[var(--color-accent-secondary)]/10",
};

export default function FolderGrid({ folders, onFolderClick, onDownloadZip }: FolderGridProps) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
      {folders.map((folder, index) => {
        const type = folder.type || "other";
        const Icon = folderIcons[type] || Folder;
        const colorClass = folderColors[type] || folderColors.other;

        return (
          <motion.div
            key={folder.id}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: index * 0.05, duration: 0.35, ease: "easeOut" }}
            onClick={() => onFolderClick(folder)}
            className="folder-card group relative"
          >
            {onDownloadZip && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onDownloadZip(folder);
                }}
                className="absolute top-2 right-2 p-1.5 rounded-lg bg-[var(--color-surface-glass)] border border-[var(--color-border-subtle)] text-[var(--color-text-tertiary)] hover:text-[var(--color-accent-primary)] hover:border-[var(--color-accent-primary)] opacity-0 group-hover:opacity-100 transition-all duration-200"
                title="Download Folder as ZIP"
              >
                <Download className="w-3.5 h-3.5" />
              </button>
            )}
            {/* Cover Thumbnail or Icon */}
            {folder.coverUrl ? (
              <div className="w-16 h-16 rounded-xl overflow-hidden ring-1 ring-white/10 transition-transform duration-300 group-hover:scale-110">
                <img
                  src={folder.coverUrl}
                  alt={folder.name}
                  className="w-full h-full object-cover"
                />
              </div>
            ) : (
              <div
                className={`folder-icon bg-gradient-to-br ${colorClass}`}
              >
                <Icon className="w-6 h-6" />
              </div>
            )}

            {/* Name + Count */}
            <div>
              <p className="text-sm font-semibold text-[var(--color-text-primary)] truncate max-w-[120px]">
                {folder.name}
              </p>
              <p className="text-xs text-[var(--color-text-tertiary)] mt-0.5">
                {folder.fileCount} {folder.fileCount === 1 ? "item" : "items"}
              </p>
            </div>
          </motion.div>
        );
      })}
    </div>
  );
}

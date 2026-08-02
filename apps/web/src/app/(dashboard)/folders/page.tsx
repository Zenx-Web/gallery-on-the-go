"use client";

/**
 * Folders Page — Full device storage browser.
 * Navigate any folder on the connected Android device,
 * download files, and explore the entire file system.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { SOCKET_EVENTS } from "@gallery/shared";
import TopBar from "@/components/TopBar";
import EmptyState from "@/components/EmptyState";
import { useDevices } from "@/contexts/DeviceContext";
import { getClientSocket } from "@/lib/socket";
import { getFileTransferManager, downloadBlob } from "@/lib/fileTransfer";
import {
  Folder,
  FolderOpen,
  File,
  FileText,
  FileImage,
  FileVideo,
  FileArchive,
  Music,
  ChevronRight,
  ArrowLeft,
  Home,
  Download,
  Loader2,
  AlertCircle,
  Smartphone,
  HardDrive,
} from "lucide-react";

// ─── Types ───────────────────────────────────────────────────────────────────

interface FolderEntry {
  id: string;
  name: string;
  path: string;
  isDirectory: boolean;
  size: number;
  mimeType?: string;
  modifiedAt?: string;
}

interface DirectoryListResponse {
  path: string;
  parentPath?: string;
  entries: FolderEntry[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
  error?: string;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const PAGE_SIZE = 60;

function formatSize(bytes: number): string {
  if (!bytes || bytes <= 0) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
  return `${(bytes / 1073741824).toFixed(2)} GB`;
}

function formatDate(iso?: string): string {
  if (!iso) return "";
  try {
    return new Date(iso).toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  } catch {
    return "";
  }
}

function getFileIcon(entry: FolderEntry) {
  if (entry.isDirectory) return Folder;
  const ext = entry.name.split(".").pop()?.toLowerCase() || "";
  const mime = entry.mimeType || "";
  if (mime.startsWith("image/") || ["jpg", "jpeg", "png", "webp", "gif", "bmp"].includes(ext))
    return FileImage;
  if (mime.startsWith("video/") || ["mp4", "mkv", "avi", "mov", "webm"].includes(ext))
    return FileVideo;
  if (mime.startsWith("audio/") || ["mp3", "flac", "aac", "wav", "ogg"].includes(ext))
    return Music;
  if (["pdf", "doc", "docx", "txt", "md", "odt", "xls", "xlsx", "csv"].includes(ext))
    return FileText;
  if (["zip", "rar", "7z", "tar", "gz"].includes(ext)) return FileArchive;
  return File;
}

function getIconColor(entry: FolderEntry): string {
  if (entry.isDirectory) return "text-[var(--color-accent)]";
  const ext = entry.name.split(".").pop()?.toLowerCase() || "";
  const mime = entry.mimeType || "";
  if (mime.startsWith("image/") || ["jpg", "jpeg", "png", "webp"].includes(ext))
    return "text-emerald-400";
  if (mime.startsWith("video/") || ["mp4", "mkv", "avi"].includes(ext)) return "text-purple-400";
  if (mime.startsWith("audio/") || ["mp3", "flac", "aac"].includes(ext)) return "text-pink-400";
  if (["pdf"].includes(ext)) return "text-red-400";
  if (["zip", "rar", "7z"].includes(ext)) return "text-yellow-400";
  return "text-[var(--color-text-muted)]";
}

// Splits a path into breadcrumb segments
function buildBreadcrumbs(path: string): { label: string; path: string }[] {
  const parts = path.replace(/\\/g, "/").split("/").filter(Boolean);
  const crumbs: { label: string; path: string }[] = [{ label: "Root", path: "/" }];
  let cumulative = "";
  for (const part of parts) {
    cumulative += "/" + part;
    crumbs.push({ label: part, path: cumulative });
  }
  return crumbs;
}

// ─── Component ───────────────────────────────────────────────────────────────

export default function FoldersPage() {
  const { selectedDevice } = useDevices();
  const [entries, setEntries] = useState<FolderEntry[]>([]);
  const [currentPath, setCurrentPath] = useState<string>("");
  const [parentPath, setParentPath] = useState<string | undefined>();
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);
  const [downloading, setDownloading] = useState<Set<string>>(new Set());
  const sentinelRef = useRef<HTMLDivElement>(null);
  const listenerRef = useRef<(() => void) | null>(null);

  // ─── Data fetching ───────────────────────────────────────────────────────

  const fetchDirectory = useCallback(
    (path: string, pageNum: number, append = false) => {
      if (!selectedDevice) return;
      const socket = getClientSocket();
      if (!socket?.connected) {
        setError("Not connected to server");
        return;
      }

      if (append) setLoadingMore(true);
      else setLoading(true);
      setError(null);

      // Clean up previous listener to avoid duplicates
      if (listenerRef.current) {
        listenerRef.current();
        listenerRef.current = null;
      }

      const timeout = setTimeout(() => {
        setLoading(false);
        setLoadingMore(false);
        setError("Timed out — device may be offline");
      }, 15000);

      const handler = (data: DirectoryListResponse) => {
        clearTimeout(timeout);
        setLoading(false);
        setLoadingMore(false);

        if (data.error) {
          setError(data.error);
          return;
        }

        setCurrentPath(data.path);
        setParentPath(data.parentPath);
        setPage(data.page);
        setHasMore(data.hasMore);

        // Sort: directories first, then files, each alphabetically
        const sorted = [...data.entries].sort((a, b) => {
          if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
          return a.name.localeCompare(b.name);
        });

        setEntries((prev) => (append ? [...prev, ...sorted] : sorted));

        // Remove this one-time listener
        socket.off(SOCKET_EVENTS.FOLDERS.LIST_RESPONSE, handler);
        listenerRef.current = null;
      };

      socket.on(SOCKET_EVENTS.FOLDERS.LIST_RESPONSE, handler);
      listenerRef.current = () => {
        socket.off(SOCKET_EVENTS.FOLDERS.LIST_RESPONSE, handler);
        clearTimeout(timeout);
      };

      socket.emit(SOCKET_EVENTS.FOLDERS.LIST, {
        deviceId: selectedDevice.id,
        path: path || undefined,
        page: pageNum,
        pageSize: PAGE_SIZE,
      });
    },
    [selectedDevice]
  );

  // Load root when device is selected
  useEffect(() => {
    if (!selectedDevice) return;
    setEntries([]);
    setCurrentPath("");
    setPage(1);
    setHasMore(false);
    fetchDirectory("", 1, false);

    return () => {
      if (listenerRef.current) {
        listenerRef.current();
        listenerRef.current = null;
      }
    };
  }, [selectedDevice, fetchDirectory]);

  // Infinite scroll sentinel
  useEffect(() => {
    if (!sentinelRef.current || !hasMore) return;
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && hasMore && !loadingMore) {
          fetchDirectory(currentPath, page + 1, true);
        }
      },
      { threshold: 0.1 }
    );
    obs.observe(sentinelRef.current);
    return () => obs.disconnect();
  }, [hasMore, loadingMore, currentPath, page, fetchDirectory]);

  // ─── Navigation ──────────────────────────────────────────────────────────

  const navigateTo = (path: string) => {
    setEntries([]);
    setPage(1);
    setHasMore(false);
    fetchDirectory(path, 1, false);
  };

  const navigateUp = () => {
    if (parentPath !== undefined) navigateTo(parentPath);
  };

  // ─── File download ────────────────────────────────────────────────────────

  const handleDownload = async (entry: FolderEntry) => {
    if (!selectedDevice || entry.isDirectory) return;
    setDownloading((prev) => new Set(prev).add(entry.id));
    try {
      const socket = getClientSocket();
      const manager = getFileTransferManager(socket);
      const { blob, fileName } = await manager.requestFile(selectedDevice.id, entry.id);
      downloadBlob(blob, fileName || entry.name);
    } catch (e) {
      console.error("Download failed:", e);
    } finally {
      setDownloading((prev) => {
        const next = new Set(prev);
        next.delete(entry.id);
        return next;
      });
    }
  };

  // ─── Breadcrumbs ──────────────────────────────────────────────────────────

  const breadcrumbs = buildBreadcrumbs(currentPath);

  // ─── Render ───────────────────────────────────────────────────────────────

  return (
    <>
      <TopBar
        title="Folders"
        subtitle="Browse all folders on the connected device"
        deviceName={selectedDevice?.deviceName}
        deviceStatus={
          selectedDevice?.status as "online" | "connecting" | "offline" | undefined
        }
      />

      <div className="p-4 sm:p-6 md:p-8 space-y-4">
        {/* No device selected */}
        {!selectedDevice && (
          <EmptyState
            icon={Smartphone}
            title="No device selected"
            description="Select a connected device from the Devices page to browse its folders."
          />
        )}

        {selectedDevice && (
          <>
            {/* Breadcrumbs */}
            <div className="flex items-center gap-1 overflow-x-auto whitespace-nowrap pb-1.5 text-xs sm:text-sm no-scrollbar">
              <button
                onClick={() => navigateTo("")}
                className="flex items-center gap-1 text-[var(--color-accent)] hover:underline shrink-0"
              >
                <HardDrive className="w-3.5 h-3.5" />
                Storage
              </button>
              {breadcrumbs.slice(1).map((crumb, i) => (
                <span key={crumb.path} className="flex items-center gap-1 shrink-0">
                  <ChevronRight className="w-3.5 h-3.5 text-[var(--color-text-muted)] shrink-0" />
                  {i === breadcrumbs.length - 2 ? (
                    <span className="text-[var(--color-text-primary)] font-medium truncate max-w-[140px] sm:max-w-[160px]">
                      {crumb.label}
                    </span>
                  ) : (
                    <button
                      onClick={() => navigateTo(crumb.path)}
                      className="text-[var(--color-accent)] hover:underline truncate max-w-[100px] sm:max-w-[120px]"
                    >
                      {crumb.label}
                    </button>
                  )}
                </span>
              ))}
            </div>

            {/* Navigation bar */}
            <div className="flex items-center gap-2">
              {parentPath !== undefined && (
                <button
                  onClick={navigateUp}
                  className="btn-ghost flex items-center gap-1.5 text-sm py-1.5 px-3 min-h-[40px]"
                >
                  <ArrowLeft className="w-4 h-4" />
                  Up
                </button>
              )}
              <button
                onClick={() => navigateTo("")}
                className="btn-ghost flex items-center gap-1.5 text-sm py-1.5 px-3 min-h-[40px]"
              >
                <Home className="w-4 h-4" />
                Root
              </button>
              {loading && (
                <span className="ml-2 flex items-center gap-1.5 text-sm text-[var(--color-text-muted)]">
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Loading…
                </span>
              )}
            </div>

            {/* Error state */}
            {error && (
              <div className="glass flex items-start gap-3 p-4 border border-red-500/20 rounded-xl">
                <AlertCircle className="w-5 h-5 text-red-400 shrink-0 mt-0.5" />
                <div>
                  <p className="text-sm font-medium text-red-400">Error</p>
                  <p className="text-sm text-[var(--color-text-muted)] mt-0.5">{error}</p>
                </div>
              </div>
            )}

            {/* Empty folder */}
            {!loading && !error && entries.length === 0 && (
              <EmptyState
                icon={FolderOpen}
                title="Empty folder"
                description="This folder has no files or subfolders, or access is restricted by Android."
              />
            )}

            {/* File / folder list */}
            {entries.length > 0 && (
              <div className="glass rounded-xl overflow-hidden">
                <AnimatePresence mode="popLayout">
                  {entries.map((entry, idx) => {
                    const Icon = getFileIcon(entry);
                    const iconColor = getIconColor(entry);
                    const isDownloading = downloading.has(entry.id);

                    return (
                      <motion.div
                        key={entry.path}
                        initial={{ opacity: 0, x: -8 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0 }}
                        transition={{ delay: Math.min(idx * 0.015, 0.3) }}
                        className={`
                          flex items-center gap-3 px-3 sm:px-4 py-3
                          border-b border-[var(--color-border)] last:border-none
                          hover:bg-white/5 transition-colors group min-h-[48px]
                          ${entry.isDirectory ? "cursor-pointer" : ""}
                        `}
                        onClick={() => {
                          if (entry.isDirectory) navigateTo(entry.path);
                        }}
                      >
                        {/* Icon */}
                        <div className={`shrink-0 ${iconColor}`}>
                          <Icon className="w-5 h-5" />
                        </div>

                        {/* Name & metadata */}
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-medium text-[var(--color-text-primary)] truncate">
                            {entry.name}
                          </p>
                          <p className="text-xs text-[var(--color-text-muted)]">
                            {entry.isDirectory ? "Folder" : formatSize(entry.size)}
                            {entry.modifiedAt && ` · ${formatDate(entry.modifiedAt)}`}
                          </p>
                        </div>

                        {/* Actions */}
                        <div className="shrink-0 flex items-center gap-2 opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
                          {entry.isDirectory ? (
                            <ChevronRight className="w-4 h-4 text-[var(--color-text-muted)]" />
                          ) : (
                            <button
                              onClick={(e) => {
                                e.stopPropagation();
                                handleDownload(entry);
                              }}
                              disabled={isDownloading}
                              className="btn-ghost p-2 rounded-lg min-w-[36px] min-h-[36px] flex items-center justify-center"
                              title="Download"
                            >
                              {isDownloading ? (
                                <Loader2 className="w-4 h-4 animate-spin" />
                              ) : (
                                <Download className="w-4 h-4" />
                              )}
                            </button>
                          )}
                        </div>
                      </motion.div>
                    );
                  })}
                </AnimatePresence>

                {/* Load-more sentinel */}
                <div ref={sentinelRef} className="h-1" />
                {loadingMore && (
                  <div className="flex items-center justify-center gap-2 py-4 text-sm text-[var(--color-text-muted)]">
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Loading more…
                  </div>
                )}
              </div>
            )}
          </>
        )}
      </div>
    </>
  );
}

"use client";

/**
 * Folders Page — Full device storage browser.
 * Navigate any folder on the connected Android device,
 * download files, and explore the entire file system.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { SOCKET_EVENTS } from "@gallery/shared";
import TopBar from "@/components/TopBar";
import EmptyState from "@/components/EmptyState";
import ImageViewer from "@/components/ImageViewer";
import { useDevices } from "@/contexts/DeviceContext";
import { getClientSocket } from "@/lib/socket";
import { getFileTransferManager, downloadBlob } from "@/lib/fileTransfer";
import { runWithConcurrency } from "@/lib/concurrency";
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
  Eye,
  Play,
  Loader2,
  AlertCircle,
  Smartphone,
  HardDrive,
  ArrowDownAZ,
  ArrowDownWideNarrow,
  ArrowUpNarrowWide,
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
// A date sort needs the entire directory in hand. The device enumerates a
// folder in NAME order, so timestamps are scattered arbitrarily across pages —
// sorting only the loaded ones would show "the oldest of the newest 60", not
// the oldest overall, and the true oldest entries would only surface after
// scrolling the whole folder in. One oversized page fetches everything: the
// device already reads and sorts the whole directory on every request and
// merely slices the result, so a bigger pageSize costs payload, not extra
// scanning. Name order keeps the cheap paged path.
const ALL_ENTRIES_PAGE_SIZE = 10000;

function pageSizeFor(order: SortOrder): number {
  return order === "name" ? PAGE_SIZE : ALL_ENTRIES_PAGE_SIZE;
}

// Matches the Gallery page — the device handles each thumbnail request as its
// own async job, so firing one per file at once floods it and most time out.
const THUMBNAIL_CONCURRENCY = 5;

const IMAGE_EXTS = ["jpg", "jpeg", "png", "webp", "gif", "bmp"];
const VIDEO_EXTS = ["mp4", "mkv", "avi", "mov", "webm"];
const AUDIO_EXTS = ["mp3", "flac", "aac", "wav", "ogg"];
const DOC_EXTS = ["pdf", "doc", "docx", "txt", "md", "odt", "xls", "xlsx", "csv"];
const ARCHIVE_EXTS = ["zip", "rar", "7z", "tar", "gz"];

function getExt(entry: FolderEntry): string {
  return entry.name.split(".").pop()?.toLowerCase() || "";
}

function isImageEntry(entry: FolderEntry): boolean {
  if (entry.isDirectory) return false;
  return (entry.mimeType || "").startsWith("image/") || IMAGE_EXTS.includes(getExt(entry));
}

function isVideoEntry(entry: FolderEntry): boolean {
  if (entry.isDirectory) return false;
  return (entry.mimeType || "").startsWith("video/") || VIDEO_EXTS.includes(getExt(entry));
}

/** Files the lightbox can render — everything else opens in a new tab. */
function isPreviewableMedia(entry: FolderEntry): boolean {
  return isImageEntry(entry) || isVideoEntry(entry);
}

type SortOrder = "name" | "newest" | "oldest";

/**
 * Directories always group above files; within each group the chosen order
 * applies. Name is the tiebreak (and the whole ordering when order is "name"),
 * which also keeps entries with no modifiedAt in a stable, sensible place —
 * FolderEntry.modifiedAt is optional.
 */
function sortEntries(list: FolderEntry[], order: SortOrder): FolderEntry[] {
  return [...list].sort((a, b) => {
    if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
    if (order !== "name") {
      const ta = a.modifiedAt ? new Date(a.modifiedAt).getTime() : 0;
      const tb = b.modifiedAt ? new Date(b.modifiedAt).getTime() : 0;
      if (ta !== tb) return order === "newest" ? tb - ta : ta - tb;
    }
    return a.name.localeCompare(b.name);
  });
}

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
  const ext = getExt(entry);
  const mime = entry.mimeType || "";
  if (mime.startsWith("image/") || IMAGE_EXTS.includes(ext)) return FileImage;
  if (mime.startsWith("video/") || VIDEO_EXTS.includes(ext)) return FileVideo;
  if (mime.startsWith("audio/") || AUDIO_EXTS.includes(ext)) return Music;
  if (DOC_EXTS.includes(ext)) return FileText;
  if (ARCHIVE_EXTS.includes(ext)) return FileArchive;
  return File;
}

function getIconColor(entry: FolderEntry): string {
  if (entry.isDirectory) return "text-[var(--color-accent)]";
  const ext = getExt(entry);
  const mime = entry.mimeType || "";
  if (mime.startsWith("image/") || IMAGE_EXTS.includes(ext)) return "text-emerald-400";
  if (mime.startsWith("video/") || VIDEO_EXTS.includes(ext)) return "text-purple-400";
  if (mime.startsWith("audio/") || AUDIO_EXTS.includes(ext)) return "text-pink-400";
  if (DOC_EXTS.includes(ext)) return "text-red-400";
  if (ARCHIVE_EXTS.includes(ext)) return "text-yellow-400";
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
  const [opening, setOpening] = useState<Set<string>>(new Set());
  const [thumbnails, setThumbnails] = useState<Record<string, string>>({});
  const [sortOrder, setSortOrder] = useState<SortOrder>("name");
  const [viewerOpen, setViewerOpen] = useState(false);
  const [viewerIndex, setViewerIndex] = useState(0);
  const [viewerUrl, setViewerUrl] = useState<string | null>(null);
  const sentinelRef = useRef<HTMLDivElement>(null);
  const listenerRef = useRef<(() => void) | null>(null);
  // False once the first directory load has happened; until then the sort
  // effect has nothing to reload and stays out of the way.
  const firstSortEffectRef = useRef(true);
  // Object URLs created for thumbnails / previews, revoked when the folder
  // changes or the page unmounts so blobs don't accumulate.
  const objectUrlsRef = useRef<string[]>([]);

  const resetPreviewState = useCallback(() => {
    objectUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
    objectUrlsRef.current = [];
    setThumbnails({});
    setOpening(new Set());
    setViewerOpen(false);
    setViewerUrl(null);
    setViewerIndex(0);
  }, []);

  // ─── Data fetching ───────────────────────────────────────────────────────

  const fetchDirectory = useCallback(
    (path: string, pageNum: number, append = false, pageSize = PAGE_SIZE) => {
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

        // Base order; the user-selected order is applied as a derived array
        // below so re-sorting never re-triggers a thumbnail refetch.
        setEntries((prev) =>
          append ? [...prev, ...sortEntries(data.entries, "name")] : sortEntries(data.entries, "name")
        );

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
        pageSize,
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
    resetPreviewState();
    fetchDirectory("", 1, false, pageSizeFor(sortOrder));
    // From here on the sort effect below is responsible for reloading.
    firstSortEffectRef.current = false;

    return () => {
      if (listenerRef.current) {
        listenerRef.current();
        listenerRef.current = null;
      }
    };
    // sortOrder is intentionally not a dependency: it is only needed at the
    // moment a device is picked, and re-running this effect on a sort change
    // would wrongly throw the user back to the root folder. The effect below
    // handles sort changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedDevice, fetchDirectory, resetPreviewState]);

  // Switching between name order and a date order changes how much of the
  // directory the device must return (a date sort needs all of it), and the
  // page cursor is only meaningful within one ordering — so reload the folder
  // the user is actually in, from the top.
  useEffect(() => {
    if (!selectedDevice) return;
    // Nothing is loaded yet (no device has been picked since mount) — the root
    // effect above will load with whatever order is current once one is.
    if (firstSortEffectRef.current) return;
    setEntries([]);
    setPage(1);
    setHasMore(false);
    resetPreviewState();
    fetchDirectory(currentPath, 1, false, pageSizeFor(sortOrder));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sortOrder]);

  // Lazily resolve thumbnails for image entries in the current folder.
  useEffect(() => {
    if (!selectedDevice || entries.length === 0) return;
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    let cancelled = false;

    // Only images — the device's thumbnail handler falls back to
    // FlutterImageCompress on the real file, which can't decode video frames
    // for path-based (`fs_*`) entries.
    const pending = entries.filter((entry) => isImageEntry(entry) && !thumbnails[entry.id]);

    runWithConcurrency(pending, THUMBNAIL_CONCURRENCY, async (entry) => {
      if (cancelled) return;
      try {
        const url = await manager.requestThumbnail(selectedDevice.id, entry.id);
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        objectUrlsRef.current.push(url);
        setThumbnails((prev) => ({ ...prev, [entry.id]: url }));
      } catch (err) {
        // Leave the entry with its file-type icon; the name is still shown.
        console.warn(`Thumbnail failed for ${entry.name || entry.id}:`, err);
      }
    });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entries, selectedDevice]);

  // Revoke every object URL on unmount.
  useEffect(() => {
    return () => {
      objectUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
    };
  }, []);

  // Infinite scroll sentinel. Only reachable for name order — a date sort
  // loads the whole directory in one request, so it comes back with no more.
  useEffect(() => {
    if (!sentinelRef.current || !hasMore) return;
    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && hasMore && !loadingMore) {
          fetchDirectory(currentPath, page + 1, true, pageSizeFor(sortOrder));
        }
      },
      { threshold: 0.1 }
    );
    obs.observe(sentinelRef.current);
    return () => obs.disconnect();
  }, [hasMore, loadingMore, currentPath, page, fetchDirectory, sortOrder]);

  // ─── Navigation ──────────────────────────────────────────────────────────

  const navigateTo = (path: string) => {
    setEntries([]);
    setPage(1);
    setHasMore(false);
    resetPreviewState();
    fetchDirectory(path, 1, false, pageSizeFor(sortOrder));
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

  // ─── Open / preview ───────────────────────────────────────────────────────
  // Media opens in the shared fullscreen viewer; other types open as a blob
  // in a new browser tab, letting the browser/OS render them.

  // Display order. The list and the viewer must both be indexed off this same
  // array, or the lightbox opens a different file than the one clicked.
  const sortedEntries = useMemo(
    () => sortEntries(entries, sortOrder),
    [entries, sortOrder]
  );

  const previewableEntries = sortedEntries.filter(isPreviewableMedia);
  const viewerEntry = previewableEntries[viewerIndex];

  const loadViewerImage = async (index: number) => {
    if (!selectedDevice) return;
    const entry = previewableEntries[index];
    if (!entry) return;

    setViewerUrl(null);
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    try {
      const { blob } = await manager.requestFile(selectedDevice.id, entry.id);
      const url = URL.createObjectURL(blob);
      objectUrlsRef.current.push(url);
      setViewerUrl(url);
    } catch {
      // Leave the viewer on the thumbnail-quality fallback.
    }
  };

  const openEntry = async (entry: FolderEntry) => {
    if (!selectedDevice || entry.isDirectory) return;

    if (isPreviewableMedia(entry)) {
      const index = previewableEntries.findIndex((e) => e.id === entry.id);
      if (index < 0) return;
      setViewerIndex(index);
      setViewerOpen(true);
      await loadViewerImage(index);
      return;
    }

    // Non-media: open the tab synchronously (still within the click's user
    // gesture) so the popup blocker allows it, then point it at the blob.
    const win = window.open("", "_blank");
    setOpening((prev) => new Set(prev).add(entry.id));
    try {
      const socket = getClientSocket();
      const manager = getFileTransferManager(socket);
      const { blob, fileName } = await manager.requestFile(selectedDevice.id, entry.id);
      const url = URL.createObjectURL(blob);
      objectUrlsRef.current.push(url);
      if (win) {
        win.location.href = url;
      } else {
        // Popup blocked — fall back to a normal download.
        downloadBlob(blob, fileName || entry.name);
      }
    } catch (e) {
      console.error("Open failed:", e);
      win?.close();
    } finally {
      setOpening((prev) => {
        const next = new Set(prev);
        next.delete(entry.id);
        return next;
      });
    }
  };

  const navigateViewer = async (direction: -1 | 1) => {
    const newIndex = viewerIndex + direction;
    if (newIndex >= 0 && newIndex < previewableEntries.length) {
      setViewerIndex(newIndex);
      await loadViewerImage(newIndex);
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

              {/* Sort control */}
              <div className="ml-auto flex items-center gap-1">
                <button
                  onClick={() => setSortOrder("name")}
                  className={`w-8 h-8 rounded-lg flex items-center justify-center transition-all ${
                    sortOrder === "name"
                      ? "bg-[var(--color-accent-primary)]/15 text-[var(--color-accent-primary)]"
                      : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-secondary)]"
                  }`}
                  title="Sort by name (A–Z)"
                  aria-label="Sort by name"
                >
                  <ArrowDownAZ className="w-4 h-4" />
                </button>
                <button
                  onClick={() => setSortOrder("newest")}
                  className={`w-8 h-8 rounded-lg flex items-center justify-center transition-all ${
                    sortOrder === "newest"
                      ? "bg-[var(--color-accent-primary)]/15 text-[var(--color-accent-primary)]"
                      : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-secondary)]"
                  }`}
                  title="Newest first"
                  aria-label="Sort newest first"
                >
                  <ArrowDownWideNarrow className="w-4 h-4" />
                </button>
                <button
                  onClick={() => setSortOrder("oldest")}
                  className={`w-8 h-8 rounded-lg flex items-center justify-center transition-all ${
                    sortOrder === "oldest"
                      ? "bg-[var(--color-accent-primary)]/15 text-[var(--color-accent-primary)]"
                      : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-secondary)]"
                  }`}
                  title="Oldest first"
                  aria-label="Sort oldest first"
                >
                  <ArrowUpNarrowWide className="w-4 h-4" />
                </button>
              </div>
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
                  {sortedEntries.map((entry, idx) => {
                    const Icon = getFileIcon(entry);
                    const iconColor = getIconColor(entry);
                    const isDownloading = downloading.has(entry.id);
                    const isOpening = opening.has(entry.id);
                    const thumbnailUrl = thumbnails[entry.id];

                    return (
                      <motion.div
                        key={entry.path}
                        initial={{ opacity: 0, x: -8 }}
                        animate={{ opacity: 1, x: 0 }}
                        exit={{ opacity: 0 }}
                        transition={{ delay: Math.min(idx * 0.015, 0.3) }}
                        className={`
                          flex items-center gap-3 sm:gap-4 px-3 sm:px-4 py-3
                          border-b border-[var(--color-border)] last:border-none
                          hover:bg-white/5 transition-colors group min-h-[64px]
                          ${entry.isDirectory ? "cursor-pointer" : ""}
                        `}
                        onClick={() => {
                          if (entry.isDirectory) navigateTo(entry.path);
                        }}
                      >
                        {/* Preview tile */}
                        <div className="shrink-0 w-16 h-16 rounded-lg overflow-hidden flex items-center justify-center bg-white/5">
                          {thumbnailUrl ? (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img
                              src={thumbnailUrl}
                              alt={entry.name}
                              loading="lazy"
                              className="w-full h-full object-cover"
                              onError={() =>
                                console.warn(`Thumbnail failed to decode for ${entry.name}`)
                              }
                            />
                          ) : (
                            <span className={iconColor}>
                              {isVideoEntry(entry) ? (
                                <Play className="w-6 h-6" />
                              ) : (
                                <Icon className="w-7 h-7" />
                              )}
                            </span>
                          )}
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
                            <>
                              <button
                                onClick={(e) => {
                                  e.stopPropagation();
                                  openEntry(entry);
                                }}
                                disabled={isOpening}
                                className="btn-ghost p-2 rounded-lg min-w-[36px] min-h-[36px] flex items-center justify-center"
                                title={isPreviewableMedia(entry) ? "Open" : "Open in new tab"}
                              >
                                {isOpening ? (
                                  <Loader2 className="w-4 h-4 animate-spin" />
                                ) : (
                                  <Eye className="w-4 h-4" />
                                )}
                              </button>
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
                            </>
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

            {/* Fullscreen preview for media entries in this folder */}
            {previewableEntries.length > 0 && (
              <ImageViewer
                isOpen={viewerOpen}
                mimeType={viewerEntry?.mimeType}
                videoUrl={
                  viewerEntry && isVideoEntry(viewerEntry) ? viewerUrl || undefined : undefined
                }
                imageUrl={
                  viewerEntry && isVideoEntry(viewerEntry)
                    ? ""
                    : viewerUrl || (viewerEntry ? thumbnails[viewerEntry.id] || "" : "")
                }
                isLoadingFull={!viewerUrl}
                imageName={viewerEntry?.name || ""}
                imageSize={viewerEntry?.size}
                imageDate={viewerEntry?.modifiedAt}
                onClose={() => setViewerOpen(false)}
                onDownload={() => {
                  if (viewerEntry) handleDownload(viewerEntry);
                }}
                onPrev={() => navigateViewer(-1)}
                onNext={() => navigateViewer(1)}
                hasPrev={viewerIndex > 0}
                hasNext={viewerIndex < previewableEntries.length - 1}
              />
            )}
          </>
        )}
      </div>
    </>
  );
}

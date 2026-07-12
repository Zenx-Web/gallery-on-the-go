"use client";

/**
 * Gallery Page — Browse photos organized by folders/albums.
 * Features: folder grid, photo grid, lightbox viewer, breadcrumb navigation.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import JSZip from "jszip";
import { SOCKET_EVENTS } from "@gallery/shared";
import type { FileItem, GalleryAlbum } from "@gallery/shared";
import TopBar from "@/components/TopBar";
import FolderGrid, { FolderItem } from "@/components/FolderGrid";
import PhotoGrid, { PhotoItem } from "@/components/PhotoGrid";
import ImageViewer from "@/components/ImageViewer";
import EmptyState from "@/components/EmptyState";
import { useDevices } from "@/contexts/DeviceContext";
import { getClientSocket } from "@/lib/socket";
import { getFileTransferManager, downloadBlob } from "@/lib/fileTransfer";
import type { EditOptions } from "@/lib/fileTransfer";
import { runWithConcurrency } from "@/lib/concurrency";

const THUMBNAIL_CONCURRENCY = 5;
const ZIP_DOWNLOAD_CONCURRENCY = 4;
const ZIP_FILE_RETRIES = 2;
// Files per ZIP chunk — each chunk is downloaded, finalized, and saved to
// disk independently, so a mid-download disconnect only loses the chunk
// currently in flight. Also bounds peak memory to one chunk's worth of
// files instead of the whole (possibly thousands-of-files) folder.
const ZIP_CHUNK_SIZE = 25;
// Incremental page size for on-screen folder browsing — kept modest so
// opening a folder with thousands of files feels instant; more pages load
// automatically as the user scrolls (see the IntersectionObserver sentinel
// below), instead of blocking on the whole folder up front.
const FOLDER_PAGE_SIZE = 40;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
import {
  ArrowLeft,
  Grid3X3,
  LayoutGrid,
  ImageIcon,
  Images,
  Smartphone,
  Download,
} from "lucide-react";

function sortByNewest(list: FileItem[]): FileItem[] {
  return [...list].sort(
    (a, b) => new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime()
  );
}

function albumToFolder(album: GalleryAlbum): FolderItem {
  return { id: album.id, name: album.name, fileCount: album.fileCount };
}

function fileToPhoto(file: FileItem): PhotoItem {
  return {
    id: file.id,
    name: file.name,
    thumbnailUrl: "", // resolved lazily, see thumbnails state below
    mimeType: file.mimeType,
    size: file.size,
    width: file.width,
    height: file.height,
    createdAt: file.createdAt,
  };
}

export default function GalleryPage() {
  const { selectedDevice } = useDevices();

  const [albums, setAlbums] = useState<GalleryAlbum[]>([]);
  const [albumsLoading, setAlbumsLoading] = useState(false);
  const [currentFolder, setCurrentFolder] = useState<FolderItem | null>(null);
  const [files, setFiles] = useState<FileItem[]>([]);
  const [filesLoading, setFilesLoading] = useState(false);
  const [filesLoadingMore, setFilesLoadingMore] = useState(false);
  const [filesHasMore, setFilesHasMore] = useState(false);
  const [filesPage, setFilesPage] = useState(1);
  const [thumbnails, setThumbnails] = useState<Record<string, string>>({});
  const [viewerOpen, setViewerOpen] = useState(false);
  const [viewerIndex, setViewerIndex] = useState(0);
  const [viewerUrl, setViewerUrl] = useState<string | null>(null);
  const [gridSize, setGridSize] = useState<"compact" | "comfortable">("comfortable");

  // ─── ZIP Download States ───
  const [zipState, setZipState] = useState<{
    active: boolean;
    status: string;
    current: number;
    total: number;
    percentage: number;
  }>({
    active: false,
    status: "",
    current: 0,
    total: 0,
    percentage: 0,
  });

  const cancelledRef = useRef<boolean>(false);
  const thumbnailUrlsRef = useRef<string[]>([]);
  const loadMoreSentinelRef = useRef<HTMLDivElement | null>(null);

  // ─── Load albums when the active device changes ───
  useEffect(() => {
    if (!selectedDevice) return;
    const socket = getClientSocket();

    setAlbumsLoading(true);
    const onAlbums = (data: { albums: GalleryAlbum[]; totalFiles: number }) => {
      setAlbums(data.albums);
      setAlbumsLoading(false);
    };
    socket.on(SOCKET_EVENTS.GALLERY.ALBUMS_RESPONSE, onAlbums);
    socket.emit(SOCKET_EVENTS.GALLERY.ALBUMS, { deviceId: selectedDevice.id });

    return () => {
      socket.off(SOCKET_EVENTS.GALLERY.ALBUMS_RESPONSE, onAlbums);
    };
  }, [selectedDevice]);

  // Fetches a single page of a folder's contents — used for incremental
  // on-screen browsing (openFolder/loadMoreFiles below).
  const fetchFolderPage = (
    folder: FolderItem,
    page: number,
    pageSize: number
  ): Promise<{ files: FileItem[]; hasMore: boolean }> => {
    const socket = getClientSocket();
    return new Promise((resolve, reject) => {
      const onAlbumFiles = (data: { files: FileItem[]; hasMore: boolean }) => {
        socket.off(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
        resolve({ files: sortByNewest(data.files), hasMore: data.hasMore });
      };

      socket.on(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
      socket.emit(SOCKET_EVENTS.GALLERY.ALBUM_FILES, {
        deviceId: selectedDevice!.id,
        albumId: folder.id,
        page,
        pageSize,
      });

      setTimeout(() => {
        socket.off(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
        reject(new Error("Failed to retrieve folder contents (timeout)"));
      }, 30000);
    });
  };

  // Fetches an ENTIRE folder in one shot — only used for ZIP downloads,
  // where the whole file list is needed up front regardless of scroll
  // position. On-screen browsing uses fetchFolderPage + loadMoreFiles
  // instead, since blocking on a full 9000-item folder before showing
  // anything is far too slow for interactive browsing.
  const fetchFolderFileList = (folder: FolderItem): Promise<FileItem[]> => {
    const socket = getClientSocket();
    return new Promise<FileItem[]>((resolve, reject) => {
      const onAlbumFiles = (data: { files: FileItem[] }) => {
        socket.off(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
        resolve(sortByNewest(data.files));
      };

      socket.on(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);

      socket.emit(SOCKET_EVENTS.GALLERY.ALBUM_FILES, {
        deviceId: selectedDevice!.id,
        albumId: folder.id,
        page: 1,
        pageSize: Math.max(folder.fileCount || 50, 1000),
      });

      // Scale the timeout with folder size — enumerating a large album can
      // take a while on the device side, and 15s was too tight for those.
      const listingTimeout = Math.min(Math.max(30000, (folder.fileCount || 0) * 50), 60000);
      setTimeout(() => {
        socket.off(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
        reject(new Error("Failed to retrieve folder contents (timeout)"));
      }, listingTimeout);
    });
  };

  // ─── Load files for the open folder ───
  // Loads just the first page immediately — more pages load automatically
  // as the user scrolls near the bottom (loadMoreFiles).
  const openFolder = useCallback(
    (folder: FolderItem) => {
      if (!selectedDevice) return;
      setCurrentFolder(folder);
      setFiles([]);
      setFilesPage(1);
      setFilesHasMore(false);
      setFilesLoading(true);

      fetchFolderPage(folder, 1, FOLDER_PAGE_SIZE)
        .then(({ files: list, hasMore }) => {
          setFiles(list);
          setFilesHasMore(hasMore);
        })
        .catch((err) => {
          console.error("Failed to load folder contents:", err);
          setFiles([]);
        })
        .finally(() => setFilesLoading(false));
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [selectedDevice]
  );

  const loadMoreFiles = useCallback(() => {
    if (!selectedDevice || !currentFolder || filesLoadingMore || !filesHasMore) return;
    const nextPage = filesPage + 1;
    setFilesLoadingMore(true);

    fetchFolderPage(currentFolder, nextPage, FOLDER_PAGE_SIZE)
      .then(({ files: list, hasMore }) => {
        // Defensive dedup — guards against any duplicate items a paged
        // device-side query might still return across page boundaries.
        setFiles((prev) => {
          const seen = new Set(prev.map((f) => f.id));
          return [...prev, ...list.filter((f) => !seen.has(f.id))];
        });
        setFilesHasMore(hasMore);
        setFilesPage(nextPage);
      })
      .catch((err) => {
        console.error("Failed to load more folder contents:", err);
        setFilesHasMore(false);
      })
      .finally(() => setFilesLoadingMore(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedDevice, currentFolder, filesPage, filesLoadingMore, filesHasMore]);

  const handleBack = () => {
    setCurrentFolder(null);
    setFiles([]);
    setFilesPage(1);
    setFilesHasMore(false);
  };

  // ─── Infinite scroll: load the next folder page when the sentinel
  // (rendered right after the grid) scrolls into view ───
  useEffect(() => {
    const el = loadMoreSentinelRef.current;
    if (!el) return;

    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0]?.isIntersecting) loadMoreFiles();
      },
      { rootMargin: "600px" }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [loadMoreFiles, files]);

  // ─── Lazily resolve thumbnails for the currently listed files ───
  useEffect(() => {
    if (!selectedDevice || files.length === 0) return;
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    let cancelled = false;

    const pendingFiles = files.filter((file) => !thumbnails[file.id]);

    // Throttled, not one request per file at once — the device handles each
    // thumbnail request as its own async job, and firing them all
    // simultaneously floods it, causing most to time out (see fileTransfer.ts).
    runWithConcurrency(pendingFiles, THUMBNAIL_CONCURRENCY, async (file) => {
      if (cancelled) return;
      try {
        const url = await manager.requestThumbnail(selectedDevice.id, file.id);
        if (cancelled) return;
        thumbnailUrlsRef.current.push(url);
        setThumbnails((prev) => ({ ...prev, [file.id]: url }));
      } catch (err) {
        // Leave the photo without a thumbnail; PhotoGrid still shows the name.
        console.warn(`Thumbnail failed for ${file.name || file.id}:`, err);
      }
    });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [files, selectedDevice]);

  // Revoke all created object URLs on unmount.
  useEffect(() => {
    return () => {
      thumbnailUrlsRef.current.forEach((url) => URL.revokeObjectURL(url));
    };
  }, []);

  const photos: PhotoItem[] = files.map((f) => ({
    ...fileToPhoto(f),
    thumbnailUrl: thumbnails[f.id] || "",
  }));

  const openViewer = async (photo: PhotoItem) => {
    const index = photos.findIndex((p) => p.id === photo.id);
    setViewerIndex(index);
    setViewerOpen(true);
    await loadViewerImage(index);
  };

  const loadViewerImage = async (index: number) => {
    if (!selectedDevice) return;
    const file = files[index];
    if (!file) return;

    setViewerUrl(null);
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    try {
      const { blob } = await manager.requestFile(selectedDevice.id, file.id);
      const url = URL.createObjectURL(blob);
      thumbnailUrlsRef.current.push(url);
      setViewerUrl(url);
    } catch {
      // Leave viewer showing the thumbnail-quality fallback below.
    }
  };

  const navigateViewer = async (direction: -1 | 1) => {
    const newIndex = viewerIndex + direction;
    if (newIndex >= 0 && newIndex < photos.length) {
      setViewerIndex(newIndex);
      await loadViewerImage(newIndex);
    }
  };

  const handleDownload = async (photo: PhotoItem) => {
    if (!selectedDevice) return;
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    try {
      const { blob, fileName } = await manager.requestFile(selectedDevice.id, photo.id);
      downloadBlob(blob, fileName || photo.name);
    } catch (err) {
      console.error("Download failed:", err);
    }
  };

  const handleDelete = async (photo: PhotoItem) => {
    if (!selectedDevice) return;
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    try {
      await manager.deleteFile(selectedDevice.id, photo.id);
      setFiles((prev) => prev.filter((f) => f.id !== photo.id));
      if (viewerOpen && photos[viewerIndex]?.id === photo.id) {
        setViewerOpen(false);
      }
    } catch (err) {
      console.error("Delete failed:", err);
      alert((err as Error).message || "Failed to delete file.");
    }
  };

  const handleRename = async (photo: PhotoItem, newName: string) => {
    if (!selectedDevice) return;
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    try {
      const finalName = await manager.renameFile(selectedDevice.id, photo.id, newName);
      setFiles((prev) =>
        prev.map((f) => (f.id === photo.id ? { ...f, name: finalName } : f))
      );
    } catch (err) {
      console.error("Rename failed:", err);
      alert((err as Error).message || "Failed to rename file.");
    }
  };

  const handleEdit = async (photo: PhotoItem, options: EditOptions) => {
    if (!selectedDevice) return;
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    try {
      const newFile = await manager.requestEdit(selectedDevice.id, photo.id, options);
      // Edits save as a new asset on Android (scoped-storage limitation —
      // see file_stream_service.dart) — swap the old entry for the new one.
      setFiles((prev) => prev.map((f) => (f.id === photo.id ? newFile : f)));
      setThumbnails((prev) => {
        const { [photo.id]: _removed, ...rest } = prev;
        return rest;
      });
      if (viewerOpen && photos[viewerIndex]?.id === photo.id) {
        // Fetch directly by the new id rather than re-running
        // loadViewerImage(viewerIndex) — the `files` array in this closure
        // is still the pre-edit snapshot until the next render.
        setViewerUrl(null);
        try {
          const { blob } = await manager.requestFile(selectedDevice.id, newFile.id);
          const url = URL.createObjectURL(blob);
          thumbnailUrlsRef.current.push(url);
          setViewerUrl(url);
        } catch {
          // Leave viewer showing the thumbnail-quality fallback.
        }
      }
    } catch (err) {
      console.error("Edit failed:", err);
      alert((err as Error).message || "Failed to save edit.");
    }
  };

  function chunkArray<T>(list: T[], size: number): T[][] {
    const chunks: T[][] = [];
    for (let i = 0; i < list.length; i += size) {
      chunks.push(list.slice(i, i + size));
    }
    return chunks;
  }

  // Downloads one chunk's files (bounded concurrency + retries) into its own
  // JSZip and returns the built blob plus how many files actually made it in.
  const downloadChunkToZip = async (
    chunkFiles: FileItem[],
    manager: ReturnType<typeof getFileTransferManager>,
    onFileSettled: () => void
  ): Promise<{ blob: Blob; downloadedCount: number }> => {
    const zip = new JSZip();
    let downloadedCount = 0;

    await runWithConcurrency(chunkFiles, ZIP_DOWNLOAD_CONCURRENCY, async (file) => {
      if (cancelledRef.current) return;

      let lastErr: unknown;
      for (let attempt = 0; attempt <= ZIP_FILE_RETRIES; attempt++) {
        if (cancelledRef.current) return;
        try {
          const { blob, fileName } = await manager.requestFile(selectedDevice!.id, file.id);
          if (cancelledRef.current) return;
          zip.file(fileName || file.name || `photo_${file.id}`, blob);
          downloadedCount++;
          lastErr = undefined;
          break;
        } catch (fileErr) {
          lastErr = fileErr;
          if (attempt < ZIP_FILE_RETRIES) await sleep(500 * (attempt + 1));
        }
      }
      if (lastErr) {
        console.warn(`Failed to download file ${file.name || file.id} after retries:`, lastErr);
      }
      onFileSettled();
    });

    const blob = await zip.generateAsync({ type: "blob" });
    return { blob, downloadedCount };
  };

  // Downloads a folder as a series of independently-valid ZIP chunk files
  // instead of one continuous archive. Each chunk is fully finalized and
  // saved to disk as soon as it completes, so a mid-download disconnect (or
  // a manual cancel) only loses the chunk currently in flight — every prior
  // chunk is already a complete, openable ZIP on disk. This also keeps peak
  // memory bounded to one chunk's worth of files instead of the whole folder.
  const downloadFolderInChunks = async (folder: FolderItem, filesList: FileItem[]) => {
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    const chunks = chunkArray(filesList, ZIP_CHUNK_SIZE);
    const totalFiles = filesList.length;
    const totalChunks = chunks.length;
    const baseName = folder.name.replace(/\s+/g, "_");
    let settledCount = 0;
    let anyChunkSaved = false;

    for (let chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      if (cancelledRef.current) break;

      const chunk = chunks[chunkIndex];
      const chunkLabel = totalChunks > 1 ? ` (part ${chunkIndex + 1} of ${totalChunks})` : "";

      const { blob, downloadedCount } = await downloadChunkToZip(chunk, manager, () => {
        settledCount++;
        setZipState({
          active: true,
          status: `Downloading files${chunkLabel} — ${settledCount} of ${totalFiles}...`,
          current: settledCount,
          total: totalFiles,
          percentage: Math.round((settledCount / totalFiles) * 100),
        });
      });

      if (downloadedCount > 0) {
        const isPartialChunk = downloadedCount < chunk.length;
        const suffix = totalChunks > 1 ? `_part${chunkIndex + 1}of${totalChunks}` : "";
        const name = `${baseName}${suffix}${isPartialChunk ? "_partial" : ""}.zip`;
        downloadBlob(blob, name);
        anyChunkSaved = true;
      }

      // A chunk that came back partial (device dropped mid-chunk) means
      // there's no point starting the next one — stop here rather than
      // grinding through remaining chunks that will just time out file by
      // file against a device that's already gone.
      if (downloadedCount < chunk.length) break;
    }

    if (!anyChunkSaved) {
      throw new Error("Could not download any files from this folder.");
    }
  };

  const downloadFolderAsZip = async (folder: FolderItem) => {
    if (!selectedDevice) return;

    setZipState({
      active: true,
      status: "Requesting folder contents...",
      current: 0,
      total: folder.fileCount || 0,
      percentage: 0,
    });
    cancelledRef.current = false;

    // Treat the device going offline mid-download exactly like a manual
    // cancel — reuses all the existing "save what we have" handling below
    // instead of waiting on each in-flight file's own 2-minute timeout.
    const statusSocket = getClientSocket();
    const onDeviceStatusChange = (data: { deviceId: string; status: string }) => {
      if (data.deviceId === selectedDevice.id && data.status === "offline") {
        cancelledRef.current = true;
        setZipState((prev) => ({ ...prev, status: "Device disconnected — saving what was downloaded..." }));
      }
    };
    statusSocket.on(SOCKET_EVENTS.DEVICE.STATUS_CHANGE, onDeviceStatusChange);

    try {
      const filesList = await fetchFolderFileList(folder);

      if (cancelledRef.current) {
        setZipState({ active: false, status: "", current: 0, total: 0, percentage: 0 });
        return;
      }

      if (!filesList || filesList.length === 0) {
        throw new Error("No files found in this folder");
      }

      setZipState((prev) => ({
        ...prev,
        total: filesList.length,
        status: `Preparing to download ${filesList.length} files...`,
      }));

      await downloadFolderInChunks(folder, filesList);
    } catch (err) {
      console.error("ZIP download failed:", err);
      alert((err as Error).message || "An error occurred while creating the ZIP archive.");
    } finally {
      statusSocket.off(SOCKET_EVENTS.DEVICE.STATUS_CHANGE, onDeviceStatusChange);
      setZipState({ active: false, status: "", current: 0, total: 0, percentage: 0 });
    }
  };

  if (!selectedDevice) {
    return (
      <>
        <TopBar title="Gallery" subtitle="No device selected" />
        <EmptyState
          icon={Smartphone}
          title="No device connected"
          description="Connect an Android device from the Devices page to browse its gallery."
        />
      </>
    );
  }

  if (selectedDevice.status !== "online") {
    return (
      <>
        <TopBar
          title="Gallery"
          deviceName={selectedDevice.deviceName}
          deviceStatus={selectedDevice.status as "online" | "connecting" | "offline"}
        />
        <EmptyState
          icon={Smartphone}
          title="Device is offline"
          description={`${selectedDevice.deviceName} isn't connected right now. Open the app on the phone to reconnect.`}
        />
      </>
    );
  }

  return (
    <>
      <TopBar
        title={currentFolder ? currentFolder.name : "Gallery"}
        subtitle={
          currentFolder
            ? `${currentFolder.fileCount} items`
            : `${albums.length} folders`
        }
        deviceName={selectedDevice.deviceName}
        deviceStatus={selectedDevice.status as "online" | "connecting" | "offline"}
      />

      <div className="p-8">
        {/* Toolbar */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            {currentFolder && (
              <motion.button
                initial={{ opacity: 0, x: -8 }}
                animate={{ opacity: 1, x: 0 }}
                onClick={handleBack}
                className="btn-ghost"
              >
                <ArrowLeft className="w-4 h-4" />
                All Folders
              </motion.button>
            )}
            {!currentFolder && (
              <div className="flex items-center gap-2">
                <ImageIcon className="w-5 h-5 text-[var(--color-accent-primary)]" />
                <h3 className="text-sm font-semibold text-[var(--color-text-primary)]">
                  Albums & Folders
                </h3>
              </div>
            )}
          </div>

          {currentFolder && (
            <div className="flex items-center gap-3">
              <button
                onClick={() => downloadFolderAsZip(currentFolder)}
                className="btn-ghost text-xs font-bold flex items-center gap-2 py-1.5 px-3 rounded-lg border border-[var(--color-border-subtle)] text-[var(--color-text-secondary)] hover:text-[var(--color-accent-primary)] hover:border-[var(--color-accent-primary)]"
                title="Download Folder as ZIP"
              >
                <Download className="w-3.5 h-3.5" />
                Download ZIP
              </button>
              <div className="flex items-center gap-1">
                <button
                  onClick={() => setGridSize("compact")}
                  className={`w-8 h-8 rounded-lg flex items-center justify-center transition-all ${
                    gridSize === "compact"
                      ? "bg-[var(--color-accent-primary)]/15 text-[var(--color-accent-primary)]"
                      : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-secondary)]"
                  }`}
                >
                  <Grid3X3 className="w-4 h-4" />
                </button>
                <button
                  onClick={() => setGridSize("comfortable")}
                  className={`w-8 h-8 rounded-lg flex items-center justify-center transition-all ${
                    gridSize === "comfortable"
                      ? "bg-[var(--color-accent-primary)]/15 text-[var(--color-accent-primary)]"
                      : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-secondary)]"
                  }`}
                >
                  <LayoutGrid className="w-4 h-4" />
                </button>
              </div>
            </div>
          )}
        </div>

        {/* Content */}
        <AnimatePresence mode="wait">
          {!currentFolder ? (
            <motion.div
              key="folders"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -12 }}
              transition={{ duration: 0.25 }}
            >
              {albumsLoading ? (
                <div className="flex items-center justify-center py-20">
                  <div className="w-6 h-6 border-2 border-[var(--color-accent-primary)] border-t-transparent rounded-full animate-spin" />
                </div>
              ) : albums.length === 0 ? (
                <EmptyState
                  icon={Images}
                  title="No photos found"
                  description="This device doesn't have any accessible photos yet."
                />
              ) : (
                <FolderGrid
                  folders={albums.map(albumToFolder)}
                  onFolderClick={openFolder}
                  onDownloadZip={downloadFolderAsZip}
                />
              )}
            </motion.div>
          ) : (
            <motion.div
              key="photos"
              initial={{ opacity: 0, y: 12 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -12 }}
              transition={{ duration: 0.25 }}
            >
              {filesLoading ? (
                <div className="flex items-center justify-center py-20">
                  <div className="w-6 h-6 border-2 border-[var(--color-accent-primary)] border-t-transparent rounded-full animate-spin" />
                </div>
              ) : (
                <>
                  <PhotoGrid photos={photos} onPhotoClick={openViewer} onDownload={handleDownload} />
                  {/* Sentinel — loads the next page automatically once it scrolls
                      into view, instead of fetching the whole (possibly
                      thousands-of-files) folder up front. */}
                  {filesHasMore && (
                    <div ref={loadMoreSentinelRef} className="flex items-center justify-center py-8">
                      <div className="w-5 h-5 border-2 border-[var(--color-accent-primary)] border-t-transparent rounded-full animate-spin" />
                    </div>
                  )}
                </>
              )}
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Image Viewer */}
      {photos.length > 0 && (
        <ImageViewer
          isOpen={viewerOpen}
          imageUrl={viewerUrl || photos[viewerIndex]?.thumbnailUrl || ""}
          imageName={photos[viewerIndex]?.name || ""}
          imageSize={photos[viewerIndex]?.size}
          imageDate={photos[viewerIndex]?.createdAt}
          onClose={() => setViewerOpen(false)}
          onDownload={() => {
            const photo = photos[viewerIndex];
            if (photo) handleDownload(photo);
          }}
          onDelete={() => {
            const photo = photos[viewerIndex];
            if (photo) handleDelete(photo);
          }}
          onRename={(newName) => {
            const photo = photos[viewerIndex];
            if (photo) handleRename(photo, newName);
          }}
          onEdit={(options) => {
            const photo = photos[viewerIndex];
            if (photo) handleEdit(photo, options);
          }}
          onPrev={() => navigateViewer(-1)}
          onNext={() => navigateViewer(1)}
          hasPrev={viewerIndex > 0}
          hasNext={viewerIndex < photos.length - 1}
        />
      )}

      {/* ZIP download progress overlay */}
      {zipState.active && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-[var(--color-bg-primary)]/40 backdrop-blur-md">
          <div className="w-full max-w-md p-6 bg-gradient-to-br from-[var(--color-surface-glass)] to-[var(--color-surface-glass-hover)] border border-[var(--color-border-subtle)] rounded-2xl shadow-2xl flex flex-col items-center gap-4 text-center">
            <div className="w-12 h-12 rounded-xl bg-[var(--color-accent-primary)]/10 flex items-center justify-center text-[var(--color-accent-primary)] animate-pulse">
              <Download className="w-6 h-6 animate-bounce" />
            </div>
            
            <div className="space-y-1">
              <h3 className="text-lg font-bold text-[var(--color-text-primary)]">
                Downloading Folder
              </h3>
              <p className="text-sm text-[var(--color-text-secondary)] font-medium max-w-xs truncate px-4">
                {zipState.status}
              </p>
            </div>

            {/* Progress Bar Container */}
            <div className="w-full space-y-1.5 mt-2 px-4">
              <div className="flex justify-between text-xs font-semibold text-[var(--color-text-tertiary)]">
                <span>{zipState.current} / {zipState.total} files</span>
                <span>{zipState.percentage}%</span>
              </div>
              <div className="w-full h-2.5 bg-[var(--color-border-subtle)] rounded-full overflow-hidden">
                <div 
                  className="h-full bg-gradient-to-r from-[var(--color-accent-primary)] to-[var(--color-accent-secondary)] transition-all duration-300 ease-out rounded-full"
                  style={{ width: `${zipState.percentage}%` }}
                />
              </div>
            </div>

            <button
              onClick={() => {
                cancelledRef.current = true;
                setZipState((prev) => ({
                  ...prev,
                  status: "Cancelling... Saving downloaded files...",
                }));
              }}
              className="mt-4 px-5 py-2 text-xs font-bold text-red-400 hover:text-red-300 bg-red-500/10 hover:bg-red-500/15 border border-red-500/20 hover:border-red-500/35 rounded-xl transition-all duration-200"
            >
              Cancel Download
            </button>
          </div>
        </div>
      )}
    </>
  );
}

"use client";

/**
 * Gallery Page — Browse photos organized by folders/albums.
 * Features: folder grid, photo grid, lightbox viewer, breadcrumb navigation.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import JSZip from "jszip";
import { downloadZip } from "client-zip";
import { SOCKET_EVENTS, PAGINATION } from "@gallery/shared";
import type { FileItem, GalleryAlbum } from "@gallery/shared";
import TopBar from "@/components/TopBar";
import FolderGrid, { FolderItem } from "@/components/FolderGrid";
import PhotoGrid, { PhotoItem } from "@/components/PhotoGrid";
import ImageViewer from "@/components/ImageViewer";
import EmptyState from "@/components/EmptyState";
import { useDevices } from "@/contexts/DeviceContext";
import { getClientSocket } from "@/lib/socket";
import { getFileTransferManager, downloadBlob } from "@/lib/fileTransfer";
import { runWithConcurrency } from "@/lib/concurrency";

const THUMBNAIL_CONCURRENCY = 5;
const ZIP_DOWNLOAD_CONCURRENCY = 4;
const ZIP_FILE_RETRIES = 2;

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

  // ─── Load files for the open folder ───
  const openFolder = useCallback(
    (folder: FolderItem) => {
      if (!selectedDevice) return;
      setCurrentFolder(folder);
      setFiles([]);
      setFilesLoading(true);

      const socket = getClientSocket();
      const onAlbumFiles = (data: { files: FileItem[] }) => {
        setFiles(sortByNewest(data.files));
        setFilesLoading(false);
        socket.off(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
      };
      socket.on(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
      socket.emit(SOCKET_EVENTS.GALLERY.ALBUM_FILES, {
        deviceId: selectedDevice.id,
        albumId: folder.id,
        page: PAGINATION.DEFAULT_PAGE,
        pageSize: PAGINATION.DEFAULT_PAGE_SIZE,
      });
    },
    [selectedDevice]
  );

  const handleBack = () => {
    setCurrentFolder(null);
    setFiles([]);
  };

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
      } catch {
        // Leave the photo without a thumbnail; PhotoGrid still shows the name.
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

  // Downloads files with bounded concurrency and yields each successful
  // result as soon as it's ready, instead of collecting them all first — lets
  // a streaming ZIP writer emit entries without holding the whole folder in
  // memory at once.
  async function* streamZipEntries(
    filesList: FileItem[],
    manager: ReturnType<typeof getFileTransferManager>,
    deviceId: string,
    onProgress: (settled: number, total: number) => void
  ): AsyncGenerator<{ name: string; input: Blob }> {
    const total = filesList.length;
    const ready: { name: string; input: Blob }[] = [];
    let nextIndex = 0;
    let settledCount = 0;
    let activeWorkers = 0;
    let wake: (() => void) | null = null;

    const notify = () => {
      if (wake) {
        const w = wake;
        wake = null;
        w();
      }
    };

    async function worker() {
      activeWorkers++;
      try {
        while (nextIndex < filesList.length) {
          if (cancelledRef.current) return;
          const file = filesList[nextIndex++];

          let result: { blob: Blob; fileName: string } | null = null;
          for (let attempt = 0; attempt <= ZIP_FILE_RETRIES; attempt++) {
            if (cancelledRef.current) return;
            try {
              const { blob, fileName } = await manager.requestFile(deviceId, file.id);
              result = { blob, fileName: fileName || file.name || `photo_${file.id}` };
              break;
            } catch (fileErr) {
              if (attempt < ZIP_FILE_RETRIES) await sleep(500 * (attempt + 1));
              else console.warn(`Failed to download file ${file.name || file.id} after retries:`, fileErr);
            }
          }

          settledCount++;
          onProgress(settledCount, total);
          if (result) ready.push({ name: result.fileName, input: result.blob });
          notify();
        }
      } finally {
        activeWorkers--;
        notify();
      }
    }

    const workers = Array.from({ length: Math.min(ZIP_DOWNLOAD_CONCURRENCY, filesList.length) }, worker);

    while (true) {
      if (ready.length > 0) {
        yield ready.shift()!;
        continue;
      }
      if (cancelledRef.current || (activeWorkers === 0 && nextIndex >= filesList.length)) {
        break;
      }
      await new Promise<void>((resolve) => {
        wake = resolve;
      });
    }

    await Promise.all(workers);
  }

  const downloadFolderViaJSZip = async (
    folder: FolderItem,
    filesList: FileItem[],
    manager: ReturnType<typeof getFileTransferManager>
  ) => {
    const zip = new JSZip();
    let downloadedCount = 0;
    const totalFiles = filesList.length;

    const saveZip = async (isPartial: boolean) => {
      const fileCountInZip = Object.keys(zip.files).length;
      if (fileCountInZip > 0) {
        setZipState((prev) => ({
          ...prev,
          percentage: 100,
          status: isPartial
            ? `Creating partial ZIP archive (${fileCountInZip} of ${totalFiles} files)...`
            : "Creating ZIP archive...",
        }));

        try {
          const zipBlob = await zip.generateAsync({ type: "blob" });
          const suffix = isPartial ? "_partial.zip" : "_gallery.zip";
          downloadBlob(zipBlob, `${folder.name.replace(/\s+/g, "_")}${suffix}`);
        } catch (genErr) {
          console.error("Failed to generate ZIP blob:", genErr);
        }
      }
    };

    try {
      let settledCount = 0;
      await runWithConcurrency(filesList, ZIP_DOWNLOAD_CONCURRENCY, async (file) => {
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

        settledCount++;
        setZipState({
          active: true,
          status: `Downloading files (${settledCount} of ${totalFiles})...`,
          current: settledCount,
          total: totalFiles,
          percentage: Math.round((settledCount / totalFiles) * 100),
        });
      });

      if (cancelledRef.current) {
        await saveZip(true);
      } else {
        await saveZip(downloadedCount < totalFiles);
      }
    } catch (err) {
      if (cancelledRef.current) {
        await saveZip(true);
      } else {
        const fileCountInZip = Object.keys(zip.files).length;
        if (fileCountInZip > 0) {
          console.error("ZIP download interrupted by error. Saving successfully downloaded files:", err);
          await saveZip(true);
        } else {
          throw err;
        }
      }
    }
  };

  // Streams the ZIP directly to disk via the File System Access API so peak
  // memory stays bounded to a handful of in-flight files (ZIP_DOWNLOAD_CONCURRENCY)
  // instead of the whole folder — avoids the OOM risk of buffering every file
  // in memory before building one giant blob (see downloadFolderViaJSZip).
  const downloadFolderViaStream = async (
    folder: FolderItem,
    filesList: FileItem[],
    manager: ReturnType<typeof getFileTransferManager>
  ) => {
    const totalFiles = filesList.length;
    const showSaveFilePicker = (window as unknown as {
      showSaveFilePicker?: (opts: unknown) => Promise<FileSystemFileHandle>;
    }).showSaveFilePicker!;

    const handle = await showSaveFilePicker({
      suggestedName: `${folder.name.replace(/\s+/g, "_")}_gallery.zip`,
      types: [{ description: "ZIP archive", accept: { "application/zip": [".zip"] } }],
    });
    const writable = await (handle as unknown as {
      createWritable: () => Promise<WritableStream<Uint8Array>>;
    }).createWritable();

    let settledCount = 0;
    const entries = streamZipEntries(filesList, manager, selectedDevice!.id, (settled, total) => {
      settledCount = settled;
      setZipState({
        active: true,
        status: `Downloading files (${settled} of ${total})...`,
        current: settled,
        total,
        percentage: Math.round((settled / total) * 100),
      });
    });

    const response = downloadZip(entries);
    try {
      await response.body!.pipeTo(writable);
    } catch (err) {
      if (cancelledRef.current) {
        setZipState((prev) => ({ ...prev, status: "Download cancelled. Removing partial file..." }));
      } else {
        throw err;
      }
    }

    if (cancelledRef.current) {
      console.warn(`ZIP download cancelled after ${settledCount} of ${totalFiles} files.`);
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

    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);

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

      const canStream = typeof window !== "undefined" && "showSaveFilePicker" in window;
      if (canStream) {
        await downloadFolderViaStream(folder, filesList, manager);
      } else {
        await downloadFolderViaJSZip(folder, filesList, manager);
      }
    } catch (err) {
      // showSaveFilePicker throws AbortError if the user dismisses the save dialog.
      if ((err as { name?: string }).name !== "AbortError") {
        console.error("ZIP download failed:", err);
        alert((err as Error).message || "An error occurred while creating the ZIP archive.");
      }
    } finally {
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
                <PhotoGrid photos={photos} onPhotoClick={openViewer} onDownload={handleDownload} />
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

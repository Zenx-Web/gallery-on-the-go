"use client";

/**
 * Gallery Page — Browse photos organized by folders/albums.
 * Features: folder grid, photo grid, lightbox viewer, breadcrumb navigation.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import JSZip from "jszip";
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
import {
  ArrowLeft,
  Grid3X3,
  LayoutGrid,
  ImageIcon,
  Images,
  Smartphone,
  Download,
} from "lucide-react";

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
        setFiles(data.files);
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

    files.forEach((file) => {
      if (thumbnails[file.id]) return;
      manager
        .requestThumbnail(selectedDevice.id, file.id)
        .then((url) => {
          if (cancelled) return;
          thumbnailUrlsRef.current.push(url);
          setThumbnails((prev) => ({ ...prev, [file.id]: url }));
        })
        .catch(() => {
          // Leave the photo without a thumbnail; PhotoGrid still shows the name.
        });
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
    const zip = new JSZip();
    let downloadedCount = 0;

    const saveZip = async (isPartial: boolean) => {
      const fileCountInZip = Object.keys(zip.files).length;
      if (fileCountInZip > 0) {
        setZipState((prev) => ({
          ...prev,
          percentage: 100,
          status: isPartial 
            ? `Creating partial ZIP archive (${fileCountInZip} of ${zipState.total || folder.fileCount} files)...` 
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
      const filesList = await new Promise<FileItem[]>((resolve, reject) => {
        const onAlbumFiles = (data: { files: FileItem[] }) => {
          socket.off(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
          resolve(data.files);
        };

        socket.on(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);

        socket.emit(SOCKET_EVENTS.GALLERY.ALBUM_FILES, {
          deviceId: selectedDevice.id,
          albumId: folder.id,
          page: 1,
          pageSize: Math.max(folder.fileCount || 50, 1000),
        });

        setTimeout(() => {
          socket.off(SOCKET_EVENTS.GALLERY.ALBUM_FILES_RESPONSE, onAlbumFiles);
          reject(new Error("Failed to retrieve folder contents (timeout)"));
        }, 15000);
      });

      if (cancelledRef.current) {
        setZipState({ active: false, status: "", current: 0, total: 0, percentage: 0 });
        return;
      }

      if (!filesList || filesList.length === 0) {
        throw new Error("No files found in this folder");
      }

      const totalFiles = filesList.length;
      setZipState((prev) => ({
        ...prev,
        total: totalFiles,
        status: `Preparing to download ${totalFiles} files...`,
      }));

      for (let i = 0; i < totalFiles; i++) {
        if (cancelledRef.current) {
          await saveZip(true);
          setZipState({ active: false, status: "", current: 0, total: 0, percentage: 0 });
          return;
        }

        const file = filesList[i];
        const fileNum = i + 1;
        setZipState({
          active: true,
          status: `Downloading ${file.name} (${fileNum} of ${totalFiles})...`,
          current: fileNum,
          total: totalFiles,
          percentage: Math.round(((fileNum - 1) / totalFiles) * 100),
        });

        try {
          const { blob, fileName } = await manager.requestFile(selectedDevice.id, file.id);
          if (cancelledRef.current) {
            await saveZip(true);
            setZipState({ active: false, status: "", current: 0, total: 0, percentage: 0 });
            return;
          }

          zip.file(fileName || file.name || `photo_${file.id}`, blob);
          downloadedCount++;
        } catch (fileErr) {
          console.warn(`Failed to download file ${file.name || file.id}:`, fileErr);
        }
      }

      if (cancelledRef.current) {
        await saveZip(true);
      } else {
        await saveZip(downloadedCount < totalFiles);
      }

      setZipState({
        active: false,
        status: "",
        current: 0,
        total: 0,
        percentage: 0,
      });
    } catch (err) {
      if (cancelledRef.current) {
        await saveZip(true);
      } else {
        const fileCountInZip = Object.keys(zip.files).length;
        if (fileCountInZip > 0) {
          console.error("ZIP download interrupted by error. Saving successfully downloaded files:", err);
          await saveZip(true);
        } else {
          console.error("ZIP download failed:", err);
          alert((err as Error).message || "An error occurred while creating the ZIP archive.");
        }
      }
      setZipState({
        active: false,
        status: "",
        current: 0,
        total: 0,
        percentage: 0,
      });
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

"use client";

/**
 * Gallery Page — Browse photos organized by folders/albums.
 * Features: folder grid, photo grid, lightbox viewer, breadcrumb navigation.
 */

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
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
            <div className="flex items-center gap-2">
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
                <FolderGrid folders={albums.map(albumToFolder)} onFolderClick={openFolder} />
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
    </>
  );
}

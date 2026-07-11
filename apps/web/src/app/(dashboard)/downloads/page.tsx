"use client";

/**
 * Downloads Page — Browse the phone's Downloads folder.
 * File list with icons, sizes, and download actions.
 */

import { useEffect, useRef, useState } from "react";
import { motion } from "framer-motion";
import { SOCKET_EVENTS, PAGINATION } from "@gallery/shared";
import type { FileItem } from "@gallery/shared";
import TopBar from "@/components/TopBar";
import EmptyState from "@/components/EmptyState";
import { useDevices } from "@/contexts/DeviceContext";
import { getClientSocket } from "@/lib/socket";
import { getFileTransferManager, downloadBlob } from "@/lib/fileTransfer";
import {
  FileText,
  FileImage,
  FileVideo,
  FileArchive,
  File,
  FolderDown,
  Download,
  MoreVertical,
  Search,
  Smartphone,
} from "lucide-react";

const fileIcons: Record<string, typeof File> = {
  pdf: FileText,
  doc: FileText,
  docx: FileText,
  txt: FileText,
  jpg: FileImage,
  jpeg: FileImage,
  png: FileImage,
  webp: FileImage,
  mp4: FileVideo,
  mkv: FileVideo,
  zip: FileArchive,
  rar: FileArchive,
};

function getFileIcon(name: string) {
  const ext = name.split(".").pop()?.toLowerCase() || "";
  return fileIcons[ext] || File;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
  return `${(bytes / 1073741824).toFixed(2)} GB`;
}

export default function DownloadsPage() {
  const { selectedDevice } = useDevices();
  const [files, setFiles] = useState<FileItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [query, setQuery] = useState("");
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ─── Initial listing ───
  useEffect(() => {
    if (!selectedDevice || selectedDevice.status !== "online") return;
    const socket = getClientSocket();
    setLoading(true);

    const onList = (data: { files: FileItem[] }) => {
      setFiles(data.files);
      setLoading(false);
    };
    socket.on(SOCKET_EVENTS.DOWNLOADS.LIST_RESPONSE, onList);
    socket.emit(SOCKET_EVENTS.DOWNLOADS.LIST, {
      deviceId: selectedDevice.id,
      page: PAGINATION.DEFAULT_PAGE,
      pageSize: PAGINATION.DEFAULT_PAGE_SIZE,
    });

    return () => {
      socket.off(SOCKET_EVENTS.DOWNLOADS.LIST_RESPONSE, onList);
    };
  }, [selectedDevice]);

  // ─── Debounced search ───
  useEffect(() => {
    if (!selectedDevice || selectedDevice.status !== "online") return;
    const socket = getClientSocket();

    if (debounceRef.current) clearTimeout(debounceRef.current);

    if (!query.trim()) {
      // Re-fetch the plain listing when the search box is cleared.
      const onList = (data: { files: FileItem[] }) => {
        setFiles(data.files);
        setLoading(false);
        socket.off(SOCKET_EVENTS.DOWNLOADS.LIST_RESPONSE, onList);
      };
      socket.on(SOCKET_EVENTS.DOWNLOADS.LIST_RESPONSE, onList);
      socket.emit(SOCKET_EVENTS.DOWNLOADS.LIST, {
        deviceId: selectedDevice.id,
        page: PAGINATION.DEFAULT_PAGE,
        pageSize: PAGINATION.DEFAULT_PAGE_SIZE,
      });
      return;
    }

    debounceRef.current = setTimeout(() => {
      setLoading(true);
      const onResults = (data: { files: FileItem[] }) => {
        setFiles(data.files);
        setLoading(false);
        socket.off(SOCKET_EVENTS.SEARCH.RESULTS, onResults);
      };
      socket.on(SOCKET_EVENTS.SEARCH.RESULTS, onResults);
      socket.emit(SOCKET_EVENTS.SEARCH.QUERY, {
        deviceId: selectedDevice.id,
        query,
        type: "filename",
      });
    }, 350);

    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, selectedDevice]);

  const handleDownload = async (file: FileItem) => {
    if (!selectedDevice) return;
    const socket = getClientSocket();
    const manager = getFileTransferManager(socket);
    try {
      const { blob, fileName } = await manager.requestFile(selectedDevice.id, file.id);
      downloadBlob(blob, fileName || file.name);
    } catch (err) {
      console.error("Download failed:", err);
    }
  };

  if (!selectedDevice) {
    return (
      <>
        <TopBar title="Downloads" subtitle="No device selected" />
        <EmptyState
          icon={Smartphone}
          title="No device connected"
          description="Connect an Android device from the Devices page to browse its downloads."
        />
      </>
    );
  }

  if (selectedDevice.status !== "online") {
    return (
      <>
        <TopBar
          title="Downloads"
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
        title="Downloads"
        subtitle="Files from your phone's Downloads folder"
        deviceName={selectedDevice.deviceName}
        deviceStatus={selectedDevice.status as "online" | "connecting" | "offline"}
      />

      <div className="p-8">
        {/* Search + Filters */}
        <div className="flex items-center gap-3 mb-6">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--color-text-tertiary)]" />
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search downloads..."
              className="input-glass pl-10"
            />
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-20">
            <div className="w-6 h-6 border-2 border-[var(--color-accent-primary)] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : files.length === 0 ? (
          <EmptyState
            icon={FolderDown}
            title={query ? "No matching files" : "No downloads found"}
            description={
              query
                ? "Try a different search term."
                : "This device's Downloads folder is empty."
            }
          />
        ) : (
          <div className="glass overflow-hidden">
            {/* Header */}
            <div className="grid grid-cols-[1fr_100px_140px_80px] gap-4 px-5 py-3 border-b border-[var(--color-border-subtle)] text-xs font-semibold text-[var(--color-text-muted)] uppercase tracking-wider">
              <span>Name</span>
              <span>Size</span>
              <span>Modified</span>
              <span className="text-right">Actions</span>
            </div>

            {/* Files */}
            {files.map((file, index) => {
              const Icon = getFileIcon(file.name);
              return (
                <motion.div
                  key={file.id}
                  initial={{ opacity: 0, x: -8 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: index * 0.04 }}
                  className="grid grid-cols-[1fr_100px_140px_80px] gap-4 px-5 py-3.5 items-center border-b border-[var(--color-border-subtle)] hover:bg-[var(--color-surface-glass-hover)] transition-colors cursor-pointer group"
                >
                  {/* Name */}
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="w-9 h-9 rounded-lg bg-[var(--color-surface-glass)] flex items-center justify-center flex-shrink-0">
                      <Icon className="w-4 h-4 text-[var(--color-text-secondary)]" />
                    </div>
                    <span className="text-sm font-medium text-[var(--color-text-primary)] truncate">
                      {file.name}
                    </span>
                  </div>

                  {/* Size */}
                  <span className="text-xs text-[var(--color-text-tertiary)]">
                    {formatSize(file.size)}
                  </span>

                  {/* Modified */}
                  <span className="text-xs text-[var(--color-text-tertiary)]">
                    {new Date(file.modifiedAt).toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                      year: "numeric",
                    })}
                  </span>

                  {/* Actions */}
                  <div className="flex items-center justify-end gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={() => handleDownload(file)}
                      className="w-7 h-7 rounded-lg hover:bg-[var(--color-surface-glass-active)] flex items-center justify-center transition-all"
                    >
                      <Download className="w-3.5 h-3.5 text-[var(--color-text-secondary)]" />
                    </button>
                    <button className="w-7 h-7 rounded-lg hover:bg-[var(--color-surface-glass-active)] flex items-center justify-center transition-all">
                      <MoreVertical className="w-3.5 h-3.5 text-[var(--color-text-secondary)]" />
                    </button>
                  </div>
                </motion.div>
              );
            })}
          </div>
        )}
      </div>
    </>
  );
}

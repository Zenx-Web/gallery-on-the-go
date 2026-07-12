/**
 * FileTransferManager — requests a file/thumbnail over the `/client` socket
 * and reassembles the chunked response (mirrors the protocol implemented on
 * the Android side in file_stream_service.dart).
 *
 * Chunk/complete/error listeners are registered once per socket and
 * dispatched to per-fileId pending requests, rather than attaching a new
 * listener per call (which would leak across repeated requests to the same
 * socket).
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import { Socket } from "socket.io-client";
import { SOCKET_EVENTS, TIMEOUTS } from "@gallery/shared";
import type { FileItem } from "@gallery/shared";

interface PendingFile {
  chunks: Uint8Array[];
  totalChunks: number;
  mimeType: string;
  fileName: string;
  resolve: (result: { blob: Blob; mimeType: string; fileName: string }) => void;
  reject: (err: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

interface PendingThumbnail {
  resolve: (url: string) => void;
  reject: (err: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

interface PendingDelete {
  resolve: () => void;
  reject: (err: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

interface PendingRename {
  resolve: (newName: string) => void;
  reject: (err: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

interface PendingEdit {
  resolve: (newFile: FileItem) => void;
  reject: (err: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

export interface EditOptions {
  rotateDegrees?: number;
  cropX?: number;
  cropY?: number;
  cropWidth?: number;
  cropHeight?: number;
  brightness?: number;
  contrast?: number;
}

function parseBinaryData(data: any): Uint8Array {
  if (data instanceof ArrayBuffer) {
    return new Uint8Array(data);
  }
  if (data instanceof Uint8Array) {
    return data;
  }
  if (data && data.type === "Buffer" && Array.isArray(data.data)) {
    return new Uint8Array(data.data);
  }
  if (Array.isArray(data)) {
    return new Uint8Array(data);
  }
  return new Uint8Array(data || []);
}

export class FileTransferManager {
  private socket: Socket;
  private pendingFiles = new Map<string, PendingFile>();
  private pendingThumbnails = new Map<string, PendingThumbnail>();
  private pendingDeletes = new Map<string, PendingDelete>();
  private pendingRenames = new Map<string, PendingRename>();
  private pendingEdits = new Map<string, PendingEdit>();
  private listenersAttached = false;

  constructor(socket: Socket) {
    this.socket = socket;
    this.attachListeners();
  }

  private attachListeners() {
    if (this.listenersAttached) return;
    this.listenersAttached = true;

    this.socket.on(SOCKET_EVENTS.FILE.CHUNK, (data: any) => {
      const pending = this.pendingFiles.get(data.fileId);
      if (!pending) return;

      pending.totalChunks = data.totalChunks;
      pending.mimeType = data.mimeType;
      pending.fileName = data.fileName;
      pending.chunks[data.chunkIndex] = parseBinaryData(data.data);
    });

    this.socket.on(SOCKET_EVENTS.FILE.COMPLETE, (data: any) => {
      const pending = this.pendingFiles.get(data.fileId);
      if (!pending) return;

      clearTimeout(pending.timeout);
      this.pendingFiles.delete(data.fileId);

      const blob = new Blob(pending.chunks as BlobPart[], {
        type: pending.mimeType || "application/octet-stream",
      });
      pending.resolve({ blob, mimeType: pending.mimeType, fileName: pending.fileName });
    });

    this.socket.on(SOCKET_EVENTS.FILE.ERROR, (data: any) => {
      const pendingFile = this.pendingFiles.get(data.fileId);
      if (pendingFile) {
        clearTimeout(pendingFile.timeout);
        this.pendingFiles.delete(data.fileId);
        pendingFile.reject(new Error(data.message || "File transfer failed"));
      }

      const pendingThumb = this.pendingThumbnails.get(data.fileId);
      if (pendingThumb) {
        clearTimeout(pendingThumb.timeout);
        this.pendingThumbnails.delete(data.fileId);
        pendingThumb.reject(new Error(data.message || "Thumbnail request failed"));
      }

      const pendingDelete = this.pendingDeletes.get(data.fileId);
      if (pendingDelete) {
        clearTimeout(pendingDelete.timeout);
        this.pendingDeletes.delete(data.fileId);
        pendingDelete.reject(new Error(data.message || "Delete failed"));
      }

      const pendingRename = this.pendingRenames.get(data.fileId);
      if (pendingRename) {
        clearTimeout(pendingRename.timeout);
        this.pendingRenames.delete(data.fileId);
        pendingRename.reject(new Error(data.message || "Rename failed"));
      }

      const pendingEdit = this.pendingEdits.get(data.fileId);
      if (pendingEdit) {
        clearTimeout(pendingEdit.timeout);
        this.pendingEdits.delete(data.fileId);
        pendingEdit.reject(new Error(data.message || "Edit failed"));
      }
    });

    this.socket.on(SOCKET_EVENTS.FILE.DELETE_RESPONSE, (data: any) => {
      const pending = this.pendingDeletes.get(data.fileId);
      if (!pending) return;
      clearTimeout(pending.timeout);
      this.pendingDeletes.delete(data.fileId);
      pending.resolve();
    });

    this.socket.on(SOCKET_EVENTS.FILE.RENAME_RESPONSE, (data: any) => {
      const pending = this.pendingRenames.get(data.fileId);
      if (!pending) return;
      clearTimeout(pending.timeout);
      this.pendingRenames.delete(data.fileId);
      pending.resolve(data.newName);
    });

    this.socket.on(SOCKET_EVENTS.FILE.EDIT_RESPONSE, (data: any) => {
      const pending = this.pendingEdits.get(data.fileId);
      if (!pending) return;
      clearTimeout(pending.timeout);
      this.pendingEdits.delete(data.fileId);
      pending.resolve(data.newFile);
    });

    this.socket.on(SOCKET_EVENTS.FILE.THUMBNAIL_RESPONSE, (data: any) => {
      const pending = this.pendingThumbnails.get(data.fileId);
      if (!pending) return;

      clearTimeout(pending.timeout);
      this.pendingThumbnails.delete(data.fileId);

      const bytes = parseBinaryData(data.data);
      // Temporary diagnostic: dump the raw payload shape + magic bytes so we
      // can tell apart "wrong format" (webp/png/etc — decodable, wrong type
      // header) from "not actually image bytes at all" (wrong parse branch,
      // truncated payload, JSON/text mistakenly sent as data).
      const magic = Array.from(bytes.slice(0, 12))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join(" ");
      console.warn(
        `Thumbnail raw payload for ${data.fileId}: rawType=${Object.prototype.toString.call(data.data)} byteLength=${bytes.byteLength} magicBytes=[${magic}]`
      );

      const blob = new Blob([bytes as BlobPart], { type: "image/jpeg" });
      pending.resolve(URL.createObjectURL(blob));
    });
  }

  requestFile(
    deviceId: string,
    fileId: string
  ): Promise<{ blob: Blob; mimeType: string; fileName: string }> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingFiles.delete(fileId);
        reject(new Error("File transfer timed out"));
      }, TIMEOUTS.FILE_STREAM_TIMEOUT);

      this.pendingFiles.set(fileId, {
        chunks: [],
        totalChunks: 0,
        mimeType: "",
        fileName: "",
        resolve,
        reject,
        timeout,
      });

      this.socket.emit(SOCKET_EVENTS.FILE.REQUEST, { deviceId, fileId });
    });
  }

  requestThumbnail(
    deviceId: string,
    fileId: string,
    width?: number,
    height?: number
  ): Promise<string> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingThumbnails.delete(fileId);
        reject(new Error("Thumbnail request timed out"));
      }, TIMEOUTS.FILE_STREAM_TIMEOUT);

      this.pendingThumbnails.set(fileId, { resolve, reject, timeout });

      this.socket.emit(SOCKET_EVENTS.FILE.THUMBNAIL_REQUEST, {
        deviceId,
        fileId,
        width,
        height,
      });
    });
  }

  deleteFile(deviceId: string, fileId: string): Promise<void> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingDeletes.delete(fileId);
        reject(new Error("Delete timed out"));
      }, TIMEOUTS.FILE_STREAM_TIMEOUT);

      this.pendingDeletes.set(fileId, { resolve, reject, timeout });
      this.socket.emit(SOCKET_EVENTS.FILE.DELETE, { deviceId, fileId });
    });
  }

  renameFile(deviceId: string, fileId: string, newName: string): Promise<string> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingRenames.delete(fileId);
        reject(new Error("Rename timed out"));
      }, TIMEOUTS.FILE_STREAM_TIMEOUT);

      this.pendingRenames.set(fileId, { resolve, reject, timeout });
      this.socket.emit(SOCKET_EVENTS.FILE.RENAME, { deviceId, fileId, newName });
    });
  }

  requestEdit(deviceId: string, fileId: string, options: EditOptions): Promise<FileItem> {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingEdits.delete(fileId);
        reject(new Error("Edit timed out"));
      }, TIMEOUTS.FILE_STREAM_TIMEOUT);

      this.pendingEdits.set(fileId, { resolve, reject, timeout });
      this.socket.emit(SOCKET_EVENTS.FILE.EDIT, { deviceId, fileId, ...options });
    });
  }
}

let manager: FileTransferManager | null = null;

export function getFileTransferManager(socket: Socket): FileTransferManager {
  if (!manager) {
    manager = new FileTransferManager(socket);
  }
  return manager;
}

/** Triggers a browser download of an already-fetched blob. */
export function downloadBlob(blob: Blob, fileName: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

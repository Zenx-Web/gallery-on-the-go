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

import { Socket } from "socket.io-client";
import { SOCKET_EVENTS, TIMEOUTS } from "@gallery/shared";

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
    });

    this.socket.on(SOCKET_EVENTS.FILE.THUMBNAIL_RESPONSE, (data: any) => {
      const pending = this.pendingThumbnails.get(data.fileId);
      if (!pending) return;

      clearTimeout(pending.timeout);
      this.pendingThumbnails.delete(data.fileId);

      const blob = new Blob([parseBinaryData(data.data)], { type: "image/jpeg" });
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

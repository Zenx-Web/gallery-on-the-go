/**
 * @gallery/shared — Type definitions
 *
 * Shared types used by both the Node.js server and Next.js frontend.
 * These mirror the database schema and WebSocket event payloads.
 */

// ─── Device ───

export enum DeviceStatus {
  ONLINE = 'online',
  CONNECTING = 'connecting',
  OFFLINE = 'offline',
}

export interface Device {
  id: string;
  deviceName: string;
  deviceModel: string | null;
  androidVersion: string | null;
  deviceToken: string;
  fcmToken: string | null;
  isActive: boolean;
  lastSeenAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface DeviceInfo {
  id: string;
  deviceName: string;
  deviceModel: string | null;
  androidVersion: string | null;
  status: DeviceStatus;
  lastSeenAt: string | null;
}

// ─── Settings ───

export interface Settings {
  id: string;
  theme: 'dark' | 'light';
  gridColumns: number;
  autoReconnect: boolean;
  notificationsEnabled: boolean;
}

// ─── Admin Auth ───

export interface AdminLoginRequest {
  email: string;
  password: string;
}

export interface AdminLoginResponse {
  token: string;
  expiresIn: string;
}

// ─── Gallery / Files ───

export interface FileItem {
  id: string;
  name: string;
  path: string;
  size: number;
  mimeType: string;
  width?: number;
  height?: number;
  duration?: number; // video duration in ms
  thumbnailId?: string;
  createdAt: string;
  modifiedAt: string;
}

export interface GalleryAlbum {
  id: string;
  name: string;
  coverThumbnailId?: string;
  fileCount: number;
}

export interface GalleryListResponse {
  albums: GalleryAlbum[];
  totalFiles: number;
}

export interface AlbumFilesRequest {
  albumId: string;
  page: number;
  pageSize: number;
}

export interface AlbumFilesResponse {
  files: FileItem[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

export interface DownloadsListResponse {
  files: FileItem[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

export interface SearchRequest {
  query: string;
  type?: 'filename' | 'date' | 'folder';
  page?: number;
  pageSize?: number;
}

export interface SearchResponse {
  files: FileItem[];
  total: number;
  page: number;
  pageSize: number;
  hasMore: boolean;
}

// ─── File Streaming ───

export interface FileRequest {
  fileId: string;
  deviceId: string;
}

export interface ThumbnailRequest {
  fileId: string;
  deviceId: string;
  width?: number;
  height?: number;
}

export interface FileChunk {
  fileId: string;
  chunkIndex: number;
  totalChunks: number;
  data: ArrayBuffer;
  mimeType: string;
  fileName: string;
}

// ─── API Response Wrapper ───

export interface ApiResponse<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

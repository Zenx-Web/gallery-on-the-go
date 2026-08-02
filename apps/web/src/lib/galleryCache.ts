/**
 * galleryCache — browser-side (IndexedDB) cache so albums, folder listings,
 * thumbnails, and full-res photos/videos already viewed stay browsable and
 * downloadable after the Android device disconnects. Server never stores
 * these bytes — this cache lives entirely in the user's own browser.
 */

import { openDB, type IDBPDatabase } from "idb";
import type { FileItem, GalleryAlbum } from "@gallery/shared";

const DB_NAME = "gallery-cache";
const DB_VERSION = 1;

interface FullResEntry {
  blob: Blob;
  mimeType: string;
  fileName: string;
}

let dbPromise: Promise<IDBPDatabase> | null = null;

function getDb(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains("albums")) db.createObjectStore("albums");
        if (!db.objectStoreNames.contains("folderFiles")) db.createObjectStore("folderFiles");
        if (!db.objectStoreNames.contains("thumbnails")) db.createObjectStore("thumbnails");
        if (!db.objectStoreNames.contains("fullres")) db.createObjectStore("fullres");
      },
    });
  }
  return dbPromise;
}

function folderKey(deviceId: string, albumId: string): string {
  return `${deviceId}:${albumId}`;
}

export async function cacheAlbums(deviceId: string, albums: GalleryAlbum[]): Promise<void> {
  const db = await getDb();
  await db.put("albums", albums, deviceId);
}

export async function getCachedAlbums(deviceId: string): Promise<GalleryAlbum[] | undefined> {
  const db = await getDb();
  return db.get("albums", deviceId);
}

export async function cacheFolderFiles(
  deviceId: string,
  albumId: string,
  files: FileItem[]
): Promise<void> {
  const db = await getDb();
  await db.put("folderFiles", files, folderKey(deviceId, albumId));
}

export async function getCachedFolderFiles(
  deviceId: string,
  albumId: string
): Promise<FileItem[] | undefined> {
  const db = await getDb();
  return db.get("folderFiles", folderKey(deviceId, albumId));
}

export async function cacheThumbnail(fileId: string, blob: Blob): Promise<void> {
  const db = await getDb();
  await db.put("thumbnails", blob, fileId);
}

export async function getCachedThumbnail(fileId: string): Promise<Blob | undefined> {
  const db = await getDb();
  return db.get("thumbnails", fileId);
}

export async function deleteCachedThumbnail(fileId: string): Promise<void> {
  const db = await getDb();
  await db.delete("thumbnails", fileId);
}

export async function cacheFullRes(
  fileId: string,
  blob: Blob,
  mimeType: string,
  fileName: string
): Promise<void> {
  const db = await getDb();
  await db.put("fullres", { blob, mimeType, fileName } satisfies FullResEntry, fileId);
}

export async function getCachedFullRes(fileId: string): Promise<FullResEntry | undefined> {
  const db = await getDb();
  return db.get("fullres", fileId);
}

export async function clearGalleryCache(): Promise<void> {
  const db = await getDb();
  await Promise.all([
    db.clear("albums"),
    db.clear("folderFiles"),
    db.clear("thumbnails"),
    db.clear("fullres"),
  ]);
}

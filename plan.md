# Remote Gallery

app name - GalleryOnTheGo

> A secure remote gallery that lets users access their Android phone's photos and downloads from anywhere without automatically uploading files to the cloud.

---

# Vision

Remote Gallery allows users to securely access files stored on their Android phone when they don't have the device with them.

Example:

You leave your phone at home.

Later, you're using another phone or your computer.

You urgently need a photo of a document.

Open:

https://gallery.zenxorg.com

Login.

Your phone securely connects.

Browse your gallery.

Open the required image.

Download only the file you need.

No automatic uploads.

No cloud gallery.

Your phone remains the source of truth.

---

# Project Goals

- Remote access to Android Gallery
- Remote access to Downloads folder
- Secure authentication
- Fast browsing
- Modern UI
- No automatic backup
- No cloud photo storage

---

# Tech Stack

## Android

Flutter

Responsibilities

- Login
- Register device
- Request Photos & Videos permission
- Request Downloads/File access (where applicable)
- Read gallery using MediaStore
- Read Downloads folder
- Connect securely to backend
- Stream requested files
- Never upload files automatically

---

## Frontend

Next.js

React

TypeScript

Tailwind CSS

Responsibilities

- Authentication
- Gallery UI
- Downloads UI
- Image Viewer
- Download button
- Search
- Device Status

---

## Backend

Node.js

Express

Socket.IO

Responsibilities

- Authentication
- JWT
- Device management
- WebSocket relay
- Secure request routing
- Session management

---

## Database

Supabase PostgreSQL

Store only:

- Users
- Devices
- Sessions
- Settings

Never store user photos.

---

# Core Features

## Authentication

- Email Login
- Password Login
- JWT Sessions
- Optional Two Factor Authentication

---

## Gallery

- Camera Photos
- Screenshots
- WhatsApp Images (if accessible)
- Albums
- Grid View
- Preview
- Fullscreen View
- Download Selected Image

---

## Downloads

Browse

Internal Download folder

Open supported files

Download selected file

---

## Search

Search by

- Filename
- Date
- Folder

---

## Device Status

Show

🟢 Online

🟡 Connecting

🔴 Offline

---

# Image Flow

Browser

↓

Backend

↓

Android App

↓

Phone Storage

↓

Android App

↓

Browser

Files are streamed.

Files are never permanently stored.

---

# Background Behaviour

If app is open

Works instantly.

If app is in background

Reconnect automatically.

If sleeping

Wake using Firebase Cloud Messaging.

If app has been force stopped

User must reopen it.

---

# Security

HTTPS

Encrypted WebSocket

JWT Authentication

Device Authentication

Rate Limiting

Only the account owner can access their files.

---

# UI Design

Dark Theme

Glassmorphism

Rounded Cards

Responsive

Smooth Animations

Minimal

Fast Loading

---

# Folder Structure

remote-gallery/

    apps/

        android/

        web/

    server/

    packages/

        shared/

    database/

    docs/

---

# Development Rules

- Use TypeScript wherever possible.
- Write clean, modular code.
- Follow SOLID principles.
- Document every module.
- Build production-ready architecture.
- Keep components reusable.
- Prioritize security and performance.
- Generate the project step by step.
- Wait for approval before moving to the next major module.



# Important Constraints

- Do NOT automatically upload user files.
- Do NOT create cloud backups.
- Do NOT store photos on the backend.
- Files should only be transferred when the user explicitly opens or downloads them.
- The Android phone is the only permanent storage location.
- Privacy and security are the highest priorities.
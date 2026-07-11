# GalleryOnTheGo — Documentation

> A secure remote gallery that lets you access your Android phone's photos and downloads from anywhere.

## Quick Start

```bash
# Install dependencies
npm install

# Build shared package
npm run build:shared

# Start server (development)
npm run dev:server

# Start web frontend (development)
npm run dev:web
```

## Architecture

```
Browser (Admin Panel) ←→ Node.js Server ←→ Android App ←→ Phone Storage
```

Files are streamed on-demand. Nothing is stored on the server.

## Environment Variables

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

See [.env.example](../.env.example) for all required variables.

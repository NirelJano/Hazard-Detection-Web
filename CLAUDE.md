# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm start          # Run local server on port 3000
npm run dev        # Alias for start
npm run deploy     # Deploy to Firebase Hosting (firebase deploy --only hosting)
```

```bash
# Admin cleanup tool (orphaned Cloudinary images)
cd admin-tools && npm install && npm run cleanup
```

```bash
# Docker
docker build -t hazard-detection .
docker run -p 3000:3000 hazard-detection
```

## Architecture

**Single-page application** — `index.html` loads `/js/app.js`, which handles client-side routing by fetching and injecting `/pages/*.html` fragments. There is no build step; all JS is ES6+ modules loaded directly in the browser.

**Runtime config injection** — `server.js` serves a dynamic `/env.js` endpoint at request time, exposing Firebase/Cloudinary/Mapbox credentials from environment variables into the browser's `window` object. This is how the frontend accesses secrets without committing them.

**ML inference on a Web Worker** — `/js/worker.js` loads a TensorFlow.js YOLO model and runs detection in a separate thread to avoid blocking the UI. The main thread sends `ImageBitmap` frames via `postMessage`; the worker returns bounding-box results after NMS (IoU threshold 0.45, adaptive confidence). Two models exist: `YOLO26n` for static uploads and `YOLO12n` for live camera detection — both in `/assets/models/`.

**Firebase stack** — Authentication (email/password + Google OAuth), Firestore for report storage, and Firebase Hosting for deployment. Security rules enforce role-based access (admin vs. user). Firestore timestamps and string dates are normalized in `/js/dashboard-*.js`.

**Image storage** — Uploaded images go to Cloudinary (not Firebase Storage). The admin cleanup tool in `/admin-tools/` removes Cloudinary images that no longer have a matching Firestore document.

**Service Worker** — `/js/worker.js` provides offline caching. Cache headers are tuned in `firebase.json`: ML models get 1-year immutable caching; `env.js` and the service worker get `no-cache`.

## Environment Variables

Requires a `.env` file at the project root (used by `server.js`):

```
CLOUDINARY_CLOUD_NAME=
CLOUDINARY_API_KEY=
CLOUDINARY_API_SECRET=
CLOUDINARY_UPLOAD_PRESET=
FIREBASE_API_KEY=
FIREBASE_AUTH_DOMAIN=
FIREBASE_PROJECT_ID=
FIREBASE_STORAGE_BUCKET=
FIREBASE_MESSAGING_SENDER_ID=
FIREBASE_APP_ID=
MAPBOX_ACCESS_TOKEN=
```

The admin tool (`admin-tools/`) also needs a Firebase service account JSON and its own `.env`.

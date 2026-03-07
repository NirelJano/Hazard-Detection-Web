# 🛣️ Road Hazard Detection System - Project Specification (v3.0)

## 1. Project Overview

A high-performance **Mobile-First Progressive Web App (PWA)** designed to identify road hazards (potholes, cracks, bumps, debris) using a custom Object Detection model. The system utilizes **client-side Machine Learning** for real-time detection, captures precise **geolocation data** (GPS + Reverse Geocoding), and manages a cloud-based reporting database via **Google Firebase**, with images stored in **Cloudinary**.

---

## 2. Technical Stack

| Category       | Technology                                          |
| -------------- | --------------------------------------------------- |
| Frontend       | HTML5, Tailwind CSS, JavaScript (ES6+)              |
| ML Engine      | TensorFlow.js (Custom YOLO26n-based Model)          |
| Performance    | Web Workers (Inference Offloading)                  |
| PWA Features   | Service Workers (Caching/Offline), manifest.json    |
| Backend/DB     | Google Firebase (Auth, Firestore, Analytics)        |
| Image Storage  | Cloudinary                                          |
| Server & Admin | Node.js (Static file server & Cleanup scripts)      |
| Maps & Geo     | Mapbox GL JS (Mapping), OSM Nominatim (Geocoding)   |
| Utilities      | exif-js (Metadata extraction for gallery uploads)   |

---

## 3. Architecture & Performance Logic

### A. Web Worker Inference Flow

To ensure a smooth UI at **60 FPS**, the ML model runs in a separate thread.

- **Main Thread:** Handles UI, `<video>` stream, and draws Bounding Boxes (BBox) on a canvas overlay. Maps are managed via Mapbox GL JS.
- **Worker Thread:** Loads the TensorFlow.js model (`worker.js`), receives `ImageBitmap` frames, runs detection, applies Non-Maximum Suppression (NMS), and returns JSON results (coordinates, labels, scores).

### B. Live Detection Optimization & Tracking

- **Inference Throttling:** Runs detection every 250ms (~4 FPS) to prevent device overheating.
- **Object Tracking (IoU):** Tracks detected hazards across frames using Intersection over Union (IoU) to ensure temporal stability, minimizing flickering.
- **Auto-Save Logic:** Requires consecutive "hits" across multiple frames before automatically saving a hazard report.
- **Cooldown & De-duplication:** 10-second cooldown per hazard type to prevent spamming the database while driving.

---

## 4. Functional Modules

### I. Authentication (Firebase Auth)

- **Sign-in Methods:** Email/Password + Google Provider.
- **Validation Rules:**
  - Password: Minimum 8 characters, at least 1 Uppercase, 1 Lowercase.
- **PWA Capabilities:** Google Sign-in specifically optimized to work inside iOS PWA standalone mode.

### II. Image Upload & Static Detection

- **Gallery/Camera Upload:** Uses `exif-js` to extract GPS metadata. If missing, attempts to use browser Geolocation API.
- **Transactional Consistency:** Uploads images directly to Cloudinary. On Firestore save failure, an automated admin tool cleans up orphaned images.
- **Reverse Geocoding:** Automatically translates GPS coordinates into human-readable street addresses before saving.

### III. Dashboard & Visualization (Split Architecture)

The dashboard logic is modularly separated for maintainability:
- `dashboard.js`: Main orchestrator.
- `dashboard-map.js`: Manages the Mapbox GL instance, custom HTML markers, popups, and fly-to animations.
- `dashboard-reports.js`: Renders the report table with dynamic badging, color-coded hazard types, pagination, and image modals.
- `dashboard-filters.js`: Handles advanced filtering by hazard type, status, date range, reporter, and search by ID/Address.

### IV. Settings & Permissions

- **Permission Toggles:** Camera, Location, Gallery access status.
- **Profile:** Theme toggling, Change Password flow.

---

## 5. Database Schema & Security (Firestore)

Role-based access is strictly enforced via Firestore Security Rules.

### Collection: `reports`
```json
{
  "id": 12,
  "hazardType": "Pothole",
  "date": "27/02/26 14:30",
  "coordinate": { "lat": 32.0853, "lng": 34.7818 },
  "address": "Herzl St 10, Tel Aviv",
  "imageUrl": "https://res.cloudinary.com/.../image.jpg",
  "reportedBy": "User Name",
  "status": "new"
}
```
- **Rules:** Authenticated users can read and create. Only admins can update or delete.

### Collection: `users`
```json
{
  "email": "user@example.com",
  "type": "user", // 'admin' or 'user'
  "createdAt": "Timestamp"
}
```
- **Rules:** Users can read and update their own profiles (cannot change their own `type`).

### Collection: `metadata`
- **Document `reportCounter`:** Used in atomic transactions to auto-increment the `id` field for new reports.
- **Rules:** Authenticated users can read and write.

---

## 6. Project Structure

```text
/
├── package.json            # Node.js project config (Express desktop server)
├── server.js               # Node.js static dev server
├── firebase-config.js      # Firebase environment configuration
├── sw.js                   # Service Worker for PWA
├── manifest.json           # PWA manifest
├── index.html              # Entry point / Redirection
│
├── admin-tools/            # Backend/Admin scripts
│   ├── cleanup.js          # Cloudinary orphaned images cleanup script
│   ├── package.json        # Admin tools dependencies
│   └── serviceAccountKey.json # Firebase Admin SDK credentials
│
├── css/
│   └── styles.css          # Tailwind + custom CSS (glassmorphism, animations)
│
├── js/
│   ├── app.js              # Global utils, Toasts, Theme management
│   ├── auth.js             # Firebase auth state & login/register logic
│   ├── dashboard.js        # Dashboard core orchestrator
│   ├── dashboard-map.js    # Mapbox integration & markers
│   ├── dashboard-reports.js# Report table rendering & pagination
│   ├── dashboard-filters.js# Dashboard search & filtering logic
│   ├── geocode.js          # Reverse geocoding (Nominatim API)
│   ├── live-detection.js   # Live camera feed, tracking, auto-save
│   ├── settings.js         # User profile and preferences
│   ├── upload.js           # Static image upload, Cloudinary api
│   └── worker.js           # TFJS Web Worker for YOLO26n inference
│
├── pages/
│   ├── login.html          # Authentication view
│   ├── register.html       # Registration view
│   ├── dashboard.html      # Main management interface
│   ├── upload.html         # Manual report creation
│   ├── live-detection.html # Dashcam-style auto-reporting
│   └── settings.html       # User configuration
│
├── assets/
│   ├── icons/              # PWA icons
│   └── model/              # TensorFlow.js model artifacts
│
└── PROJECT_SPEC.md         # This specification document
```

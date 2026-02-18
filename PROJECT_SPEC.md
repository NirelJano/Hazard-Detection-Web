# 🛣️ Road Hazard Detection System - Project Specification (v3.0)

## 1. Project Overview

A high-performance **Mobile-First Progressive Web App (PWA)** designed to identify road hazards (potholes, cracks, etc.) using a custom Object Detection model. The system utilizes **client-side Machine Learning** for real-time detection, captures precise **geolocation data** (GPS + Reverse Geocoding), and manages a cloud-based reporting database via **Google Firebase**.

---

## 2. Technical Stack

| Category       | Technology                                          |
| -------------- | --------------------------------------------------- |
| Frontend       | HTML5, Tailwind CSS, JavaScript (ES6+)              |
| ML Engine      | TensorFlow.js (Custom Model)                        |
| Performance    | Web Workers (Inference Offloading)                  |
| PWA Features   | Service Workers (Caching/Offline), manifest.json    |
| Backend/DB     | Google Firebase (Auth, Firestore)                   |
| Server         | Node.js (Static file server)                        |
| Maps & Geo     | Google Maps JS API (Mapping & Reverse Geocoding)    |
| Utilities      | exif-js (Metadata extraction for gallery uploads)   |

---

## 3. Architecture & Performance Logic

### A. Web Worker Inference Flow

To ensure a smooth UI at **60 FPS**, the ML model runs in a separate thread.

- **Main Thread:** Handles UI, `<video>` stream, and draws Bounding Boxes (BBox) on a canvas overlay.
- **Worker Thread:** Loads the TensorFlow.js model, receives `ImageBitmap` frames, runs detection, and returns JSON results (coordinates, labels, scores).

### B. Live Detection Optimization

- **Inference Throttling:** Run detection every 200-300ms (approx. 3-5 FPS) to prevent device overheating.
- **NMS (Non-Maximum Suppression):** Filter overlapping detection boxes.
- **Auto-Save Logic:** If `confidence > 0.80`, trigger an automatic report.
- **De-duplication:** 5-second cooldown or distance-based check to prevent multiple reports for the same hazard.

---

## 4. Functional Modules

### I. Authentication (Firebase Auth)

- **Sign-in Methods:** Email/Password + Google Provider.
- **Validation Rules:**
  - Password: Minimum 8 characters, at least 1 Uppercase, 1 Lowercase.
  - Fields: Username, Email, Password, Password Confirmation.

### II. Image Upload & Static Detection

- **Gallery Upload:** Uses `exif-js` to extract GPS metadata. If missing, the app blocks the report or asks for manual input.
- **Live Capture:** Captures the browser's current Geolocation at the exact moment of the shutter press.
- **Logic:** A "Save Report" button appears only if: `(Model Detected Hazard == True) AND (GPS Data == Present)`.

### III. Dashboard & Visualization

- **Map View:** Google Map (Israel focus) with custom markers for different hazard types.
- **Report Log:** A clean, searchable table/list including:
  - ID, Hazard Type, Address (Text), Date, Status, Image Thumbnail.

### IV. Settings & Permissions

- **Permission Toggles:** Camera, Location, Gallery access status.
- **Profile:** "Change Password" flow requiring Old Password, New Password, and Confirmation.

---

## 5. Database Schema (Firestore)

### Collection: `reports`

```json
{
  "id": "UUID_AUTO_GEN",
  "hazardType": "Pothole",
  "date": "ServerTimestamp",
  "coordinate": { "lat": 32.0853, "lng": 34.7818 },
  "address": "Herzl St 10, Tel Aviv",
  "imageUrl": "Image_URL (external storage)",
  "reportedBy": "User_UID",
  "status": "open"
}
```

> **Status Values:** `open` | `in-progress` | `fixed`

---

## 6. Implementation Roadmap

### Phase 1: Foundation
- Initialize Firebase Project.
- Setup PWA `manifest.json` and a basic Service Worker for offline asset caching.

### Phase 2: Authentication
- Build the login/register UI with Firebase Auth and the specified password validation.

### Phase 3: Dashboard & Maps
- Implement the Google Maps integration and the Firestore real-time listener for the report log.

### Phase 4: ML Infrastructure
- Setup the `worker.js` file.
- Implement the bridge between the Main UI thread and the TensorFlow.js worker.

### Phase 5: Detection Pages
- Build the Static Upload page with `exif-js`.
- Build the Live Detection page with `requestAnimationFrame` and Reverse Geocoding integration.

### Phase 6: Polish
- Add Tailwind transitions, loading states, and mobile-responsive adjustments.

---

## 7. Project Structure

```
/
├── package.json            # Node.js project config
├── server.js               # Node.js static dev server
├── index.html              # Entry point / Login page
├── manifest.json           # PWA manifest
├── sw.js                   # Service Worker
├── firebase-config.js      # Firebase initialization
│
├── css/
│   └── styles.css          # Tailwind + custom styles
│
├── js/
│   ├── app.js              # Main application router / SPA logic
│   ├── auth.js             # Firebase Auth logic
│   ├── dashboard.js        # Dashboard & Map logic
│   ├── upload.js           # Static image upload + detection
│   ├── live-detection.js   # Live camera detection page
│   ├── settings.js         # Settings & permissions page
│   └── worker.js           # TensorFlow.js Web Worker
│
├── pages/
│   ├── login.html          # Login page
│   ├── register.html       # Registration page
│   ├── dashboard.html      # Dashboard with map + report log
│   ├── upload.html         # Image upload & static detection
│   ├── live-detection.html # Live camera detection
│   └── settings.html       # Settings & permissions
│
├── assets/
│   ├── icons/              # PWA icons
│   └── model/              # TensorFlow.js model files
│
└── PROJECT_SPEC.md         # This file
```

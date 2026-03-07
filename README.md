# 🛣️ Road Hazard Detection System

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/platform-PWA-success.svg" alt="Platform">
  <img src="https://img.shields.io/badge/TensorFlow.js-YOLO26n-orange.svg" alt="ML">
  <img src="https://img.shields.io/badge/Firebase-Firestore-yellow.svg" alt="DB">
  <img src="https://img.shields.io/badge/Mapbox-GL_JS-blueviolet.svg" alt="Maps">
  <img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License">
</p>

## 📌 Overview

A high-performance **Mobile-First Progressive Web App (PWA)** designed to identify road hazards such as potholes, cracks, bumps, and debris using a custom Object Detection model. The system utilizes **client-side Machine Learning** for real-time detection, captures precise **geolocation data** (GPS + Reverse Geocoding), and manages a cloud-based reporting database via **Google Firebase**, with images stored securely in **Cloudinary**.

---

## ✨ Key Features

- **📱 Mobile-First PWA:** Installable directly on iOS/Android as a standalone app, fully optimized for mobile devices.
- **🧠 Client-Side Machine Learning:** Custom TensorFlow.js YOLO26n model runs in your browser using a dedicated Web Worker to ensure a buttery smooth UI at 60 FPS.
- **📍 Live Detection & Tracking:** Real-time object tracking across frames utilizing Intersection over Union (IoU) with a built-in anti-spam cooldown mechanism.
- **🗺️ Interactive Map Dashboard:** Mapbox GL JS integration with custom markers, popups, and intuitive reverse geocoding via OSM Nominatim.
- **☁️ Cloud & Analytics:** Firebase Authentication (Email/Password + Google Login), Firestore Database with role-based access, and direct Cloudinary image uploads.
- **🔒 Secure Architecture:** Strict Firestore Security Rules ensuring transactional consistency and robust data protection.

---

## 🛠️ Technical Stack

### Frontend & UI
- **HTML5 & Vanilla CSS** (Tailwind CSS, Glassmorphism, Custom Animations)
- **Vanilla JavaScript (ES6+)**
- **Service Workers:** Offline support and caching mechanism
- **Web Workers:** Inference offloading to an isolated thread

### ML Engine
- **TensorFlow.js**
- **Custom YOLO26n-based Model**

### Backend & Cloud Infrastructure
- **Google Firebase:** Authentication, Firestore DB, Analytics
- **Cloudinary:** Efficient Image Storage
- **Node.js:** Local server and Cloudinary orphaned images cleanup scripts

### Maps & Geolocation
- **Mapbox GL JS**
- **OSM Nominatim API** (Reverse Geocoding)
- **exif-js** (GPS metadata extraction for gallery uploads)

---

## 🚀 Getting Started

### Prerequisites
Make sure you have [Node.js](https://nodejs.org/) installed on your local machine.

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/road-hazard-detection.git
   cd road-hazard-detection
   ```

2. **Install local dependencies (Server & Admin Tools):**
   ```bash
   npm install
   cd admin-tools && npm install && cd ..
   ```

3. **Environment Configuration:**
   - Configure Firebase locally in `firebase-config.js` and `.firebaserc`.
   - Setup your environment variables using the `.env` template (Cloudinary URL, Mapbox Token, Firebase Config).
   - Place your `serviceAccountKey.json` inside the `admin-tools/` directory for cleanup admin scripts.

4. **Run the local development server:**
   ```bash
   npm start
   ```
   The application will be accessible at `http://localhost:3000`.

---

## 🏗️ Project Architecture

To ensure a continuous UI at **60 FPS**, the ML model inference is offloaded to a separate Web Worker thread:
- **Main Thread:** Handles UI execution, `<video>` rendering stream, Mapbox GL updates, and bounding boxes drawing dynamically on the canvas.
- **Worker Thread:** Initializes TensorFlow.js (`worker.js`), receives `ImageBitmap` frames from the camera, applies object detection + NMS (Non-Maximum Suppression), and safely returns the geometric results without blocking the UI.

---

## 📱 Screenshots
*(Add your screenshots here)*

| Live Detection | Dashboard Map | Report Table |
|:---:|:---:|:---:|
| <img src="https://via.placeholder.com/250x500.png?text=Live+Detection" width="200" alt="Live detection view"/> | <img src="https://via.placeholder.com/250x500.png?text=Map+Dashboard" width="200" alt="Dashboard map view"/> | <img src="https://via.placeholder.com/250x500.png?text=Report+Table" width="200" alt="Report table view"/> |

*(Replace the placeholder URLs with actual app screenshots)*

---

## 🛡️ Security Rules

All queries to the Firestore database are verified by Firebase Security Rules.
- **Users:** Read context is open to authenticated users; users can update their own profile data without impersonating an admin.
- **Reports:** Authenticated users can create and read. Only system admins are officially authorized to modify/delete reports or approve invalid reports.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page or open a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

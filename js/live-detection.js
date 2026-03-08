// ============================================
// Live Detection Module (Camera + Real-time)
// ============================================

import { auth, db } from '../firebase-config.js';
import { showToast } from './app.js';
import { uploadToCloudinary } from './upload.js';
import { reverseGeocode } from './geocode.js';
import {
    collection,
    doc,
    addDoc,
    runTransaction,
    GeoPoint,
    query,
    where,
    orderBy,
    limit,
    getDocs
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';

let worker = null;
let videoStream = null;
let isDetecting = false;
let isModelReady = false;
let detectionInterval = null;
let gpsInterval = null;       // Periodic GPS refresh interval
let cachedGPS = null;          // GPS position cached from user-gesture context
let uiTracks = [];
let animationFrameId = null;

const DETECTION_INTERVAL_MS = 250; // ~4 FPS inference

// Cooldown: prevent saving the same hazard type more than once per 30 seconds
const SAVE_COOLDOWN_MS = 10_000;
const recentlySaved = new Map(); // label -> timestamp

export function init() {
    setupWorker();
    setupCamera();
    setupControls();
}

// ---------- Web Worker ----------
function setupWorker() {
    if (worker) worker.terminate();
    worker = new Worker('js/worker.js');

    worker.onmessage = (e) => {
        const { type, data } = e.data;
        switch (type) {
            case 'model-loaded':
                console.log('[Live] Model ready');
                isModelReady = true;
                const overlay = document.getElementById('model-loading-overlay');
                if (overlay) overlay.classList.add('hidden');
                updateStatus('Model loaded. Tap Start to begin.');
                break;
            case 'detection-result':
                handleLiveDetection(data.activeTracks);
                break;
            case 'report-hazard':
                data.forEach(report => {
                    autoSaveReport(report);
                });
                break;
            case 'error':
                console.error('[Live] Worker error:', data);
                break;
        }
    };

    // Defer model loading until after First Paint for better LCP
    const startModelLoad = () => worker.postMessage({ type: 'load-model', target: 'live' });
    if ('requestIdleCallback' in self) {
        requestIdleCallback(startModelLoad);
    } else {
        setTimeout(startModelLoad, 100);
    }
}

// ---------- Camera Setup ----------
async function setupCamera() {
    const video = document.getElementById('camera-feed');
    if (!video) return;

    try {
        videoStream = await navigator.mediaDevices.getUserMedia({
            video: {
                facingMode: 'environment', // Rear camera
                width: { ideal: 1280 },
                height: { ideal: 720 },
            },
            audio: false,
        });
        video.srcObject = videoStream;
        await video.play();
        console.log('[Live] Camera started');
    } catch (err) {
        console.error('[Live] Camera error:', err);
        showToast('Camera access denied. Please enable permissions.', 'error');
    }
}

// ---------- Controls ----------
function setupControls() {
    const startBtn = document.getElementById('start-detection-btn');
    const stopBtn = document.getElementById('stop-detection-btn');

    if (startBtn) {
        startBtn.addEventListener('click', () => {
            isDetecting = true;
            uiTracks = [];
            startDetectionLoop();
            startRenderLoop();
            startGPSUpdates(); // Request GPS in response to user gesture
            startBtn.classList.add('hidden');
            stopBtn?.classList.remove('hidden');
            updateStatus('Detecting...');
        });
    }

    if (stopBtn) {
        stopBtn.addEventListener('click', () => {
            isDetecting = false;
            clearInterval(detectionInterval);
            if (animationFrameId) cancelAnimationFrame(animationFrameId);
            stopGPSUpdates();
            stopBtn.classList.add('hidden');
            startBtn?.classList.remove('hidden');
            updateStatus('Detection paused');
            uiTracks = [];
            drawOverlay([]); // clear overlay
        });
    }
}

// ---------- GPS Helpers ----------
function startGPSUpdates() {
    // Fetch immediately, then refresh every 10s
    fetchGPS();
    gpsInterval = setInterval(fetchGPS, 10_000);
}

function stopGPSUpdates() {
    clearInterval(gpsInterval);
    gpsInterval = null;
}

function fetchGPS() {
    if (!('geolocation' in navigator)) return;

    // Some browsers enforce user-gesture policy strictly.
    // If not called directly from a click, it may warn/fail.
    try {
        navigator.geolocation.getCurrentPosition(
            (pos) => {
                cachedGPS = { lat: pos.coords.latitude, lng: pos.coords.longitude, speed: pos.coords.speed || 0 };
            },
            (err) => {
                console.warn('[Live] GPS fetch failed:', err.message);
            },
            { enableHighAccuracy: true, timeout: 8000, maximumAge: 5000 }
        );
    } catch (e) {
        console.warn('[Live] GPS fetch error:', e.message);
    }
}

// ---------- Detection Loop ----------
function startDetectionLoop() {
    const video = document.getElementById('camera-feed');
    if (!video) return;

    detectionInterval = setInterval(async () => {
        if (!isDetecting || video.readyState < 2) return;

        try {
            // Snapshot the current frame BEFORE transferring to worker
            const bitmap = await createImageBitmap(video);
            const speed = cachedGPS ? cachedGPS.speed || 0 : 0;
            worker.postMessage({ type: 'detect', image: bitmap, speed }, [bitmap]);
        } catch (err) {
            // Ignore frame capture errors
        }
    }, DETECTION_INTERVAL_MS);
}

// ---------- Handle Live Detections ----------
function handleLiveDetection(activeTracks) {
    const currentUiTracks = [];
    activeTracks.forEach(track => {
        const existing = uiTracks.find(t => t.id === track.id);
        if (existing) {
            existing.targetBbox = track.bbox;
            existing.label = track.label;
            existing.state = track.state;
            existing.age = track.age;
            currentUiTracks.push(existing);
        } else {
            currentUiTracks.push({
                id: track.id,
                label: track.label,
                state: track.state,
                age: track.age,
                currentBbox: [...track.bbox],
                targetBbox: [...track.bbox]
            });
        }
    });
    uiTracks = currentUiTracks;
}

// ---------- Render Loop (60 FPS) ----------
function startRenderLoop() {
    function render() {
        if (!isDetecting) return;

        // Fast UI Tracking (EMA with alpha = 0.2)
        const ALPHA = 0.2;
        uiTracks.forEach(track => {
            for (let i = 0; i < 4; i++) {
                track.currentBbox[i] += (track.targetBbox[i] - track.currentBbox[i]) * ALPHA;
            }
        });

        drawOverlay(uiTracks);
        animationFrameId = requestAnimationFrame(render);
    }
    render();
}

// ---------- Draw Overlay ----------
function drawOverlay(tracks) {
    const canvas = document.getElementById('live-canvas');
    const video = document.getElementById('camera-feed');
    if (!canvas || !video) return;

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    if (!tracks || tracks.length === 0) return;

    tracks.forEach((track) => {
        const [x, y, w, h] = track.currentBbox;

        // Color based on state
        let color = '#facc15'; // tentative: yellow
        if (track.state === 'confirmed') color = '#22c55e'; // confirmed: green
        if (track.state === 'vanished') color = '#ef4444'; // vanished: red

        // Box
        ctx.strokeStyle = color;
        ctx.lineWidth = 3;
        ctx.strokeRect(x, y, w, h);

        // Label background
        ctx.fillStyle = color;
        const labelText = track.state === 'confirmed' ? track.label : `${track.label} (?)`;
        ctx.font = 'bold 14px Inter';
        const tw = ctx.measureText(labelText).width;
        ctx.fillRect(x, y - 22, tw + 8, 22);

        // Label text
        ctx.fillStyle = '#fff';
        ctx.fillText(labelText, x + 4, y - 6);
    });
}

function getDistanceFromLatLonInM(lat1, lon1, lat2, lon2) {
    const R = 6371e3; // Radius of the earth in m
    const dLat = deg2rad(lat2 - lat1);
    const dLon = deg2rad(lon2 - lon1);
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

function deg2rad(deg) {
    return deg * (Math.PI / 180);
}

// ---------- Auto-Save Report ----------
async function autoSaveReport(report) {
    const user = auth.currentUser;
    if (!user) {
        // close unused bitmap
        try { report.bitmap.close(); } catch (e) { }
        return;
    }

    // Cooldown guard: skip if we saved this hazard type recently
    const now = Date.now();
    const lastSaved = recentlySaved.get(report.label);
    if (lastSaved && (now - lastSaved) < SAVE_COOLDOWN_MS) {
        console.log(`[Live] Skipping auto-save for ${report.label} – local cooldown active (${Math.round((SAVE_COOLDOWN_MS - (now - lastSaved)) / 1000)}s remaining)`);
        try { report.bitmap.close(); } catch (e) { }
        return;
    }
    // Mark this label as saved locally
    recentlySaved.set(report.label, now);

    // Use the cached GPS position (set when user clicked Start)
    if (!cachedGPS) {
        console.warn('[Live] No cached GPS for auto-save – waiting for location');
        return;
    }
    const gps = cachedGPS;

    try {
        // Spatial Deduplication (Check Firestore for recent duplicates within 5m)
        // Removed orderBy and limit to avoid requiring a composite index. We handle sorting locally.
        const q = query(collection(db, 'reports'), where('hazardType', '==', report.label));
        const recentSnap = await getDocs(q);

        const recentDocs = [];
        recentSnap.forEach(snap => recentDocs.push(snap.data()));
        recentDocs.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
        const topRecent = recentDocs.slice(0, 10);

        let shouldSkip = false;
        topRecent.forEach(data => {
            if (data.coordinate && data.createdAt) {
                const ageMs = Date.now() - data.createdAt;
                if (ageMs < 30_000) { // 30 seconds wait window
                    const dist = getDistanceFromLatLonInM(gps.lat, gps.lng, data.coordinate.latitude, data.coordinate.longitude);
                    if (dist < 5) shouldSkip = true;
                }
            }
        });

        if (shouldSkip) {
            console.log(`[Live] Duplicate detected in DB within 5m and 30s. Skipping.`);
            try { report.bitmap.close(); } catch (e) { }
            return;
        }

        // Reverse-geocode coordinates → address (required)
        let address;
        try {
            address = await reverseGeocode(gps.lat, gps.lng);
        } catch (geoErr) {
            console.warn('[Live] Reverse geocoding failed, skipping auto-save:', geoErr);
            try { report.bitmap.close(); } catch (e) { }
            return;
        }

        // Format date
        const nowDate = new Date();
        const dd = String(nowDate.getDate()).padStart(2, '0');
        const mm = String(nowDate.getMonth() + 1).padStart(2, '0');
        const yy = String(nowDate.getFullYear()).slice(-2);
        const hh = String(nowDate.getHours()).padStart(2, '0');
        const min = String(nowDate.getMinutes()).padStart(2, '0');
        const formattedDate = `${dd}/${mm}/${yy} ${hh}:${min}`;

        // Upload image if we have it
        let imageUrl = '';
        if (report.bitmap) {
            try {
                // Convert ImageBitmap to canvas to draw bounding box
                const canvas = document.createElement('canvas');
                canvas.width = report.bitmap.width;
                canvas.height = report.bitmap.height;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(report.bitmap, 0, 0);

                // Draw bbox
                const [x, y, bw, bh] = report.bbox;
                ctx.strokeStyle = '#22c55e';
                ctx.lineWidth = 3;
                ctx.strokeRect(x, y, bw, bh);

                ctx.fillStyle = '#22c55e';
                const scoreText = `${report.label} ${(report.score * 100).toFixed(0)}%`;
                ctx.font = 'bold 24px Inter';
                const tw = ctx.measureText(scoreText).width;
                ctx.fillRect(x, y - 32, tw + 16, 32);
                ctx.fillStyle = '#fff';
                ctx.fillText(scoreText, x + 8, y - 8);

                const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.8));
                if (blob) {
                    imageUrl = await uploadToCloudinary(blob, `hazard_live_${Date.now()}.jpg`);
                }
            } catch (blurErr) {
                console.warn('[Live] Image upload failed', blurErr);
            } finally {
                // Close the bitmap to free memory
                try { report.bitmap.close(); } catch (e) { }
            }
        }

        // Get next sequential ID via transaction
        const counterRef = doc(db, 'metadata', 'reportCounter');
        let nextId = 1;
        await runTransaction(db, async (transaction) => {
            const counterDoc = await transaction.get(counterRef);
            if (counterDoc.exists()) {
                nextId = (counterDoc.data().count || 0) + 1;
            }
            transaction.set(counterRef, { count: nextId });
        });

        // Save report as a new document (Firestore auto-generates the doc ID)
        await addDoc(collection(db, 'reports'), {
            id: nextId,
            hazardType: report.label,
            date: formattedDate,
            createdAt: Date.now(), // timestamp for deduplication
            coordinate: new GeoPoint(gps.lat, gps.lng),
            address: address,
            imageUrl: imageUrl,
            reportedBy: user.displayName || user.email || 'Unknown User',
            status: 'new',
        });

        showToast(`Auto-saved: ${report.label}`, 'success');
    } catch (err) {
        console.error('[Live] Auto-save error:', err);
        recentlySaved.delete(report.label);
    }
}

// ---------- Helpers ----------
function updateStatus(text) {
    const el = document.getElementById('detection-status');
    if (el) el.textContent = text;
}

// Cleanup when leaving page
window.addEventListener('beforeunload', () => {
    if (videoStream) {
        videoStream.getTracks().forEach((t) => t.stop());
    }
    if (worker) worker.terminate();
    clearInterval(detectionInterval);
    if (animationFrameId) cancelAnimationFrame(animationFrameId);
    clearInterval(gpsInterval);
});

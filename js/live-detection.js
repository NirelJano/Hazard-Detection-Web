// ============================================
// Live Detection Module (Camera + Real-time)
// ============================================

import { auth, db } from '../firebase-config.js';
import { showToast } from './app.js';
import {
    collection,
    doc,
    runTransaction,
    GeoPoint
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';

let worker = null;
let videoStream = null;
let isDetecting = false;
let detectionInterval = null;
let lastSaveTime = 0;
const SAVE_COOLDOWN = 5000; // 5-second de-duplication
const CONFIDENCE_THRESHOLD = 0.45;
const DETECTION_INTERVAL_MS = 250; // ~4 FPS inference

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
                updateStatus('Model loaded. Tap Start to begin.');
                break;
            case 'detection-result':
                handleLiveDetection(data);
                break;
            case 'error':
                console.error('[Live] Worker error:', data);
                break;
        }
    };

    worker.postMessage({ type: 'load-model' });
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
            startDetectionLoop();
            startBtn.classList.add('hidden');
            stopBtn?.classList.remove('hidden');
            updateStatus('Detecting...');
        });
    }

    if (stopBtn) {
        stopBtn.addEventListener('click', () => {
            isDetecting = false;
            clearInterval(detectionInterval);
            stopBtn.classList.add('hidden');
            startBtn?.classList.remove('hidden');
            updateStatus('Detection paused');
        });
    }
}

// ---------- Detection Loop ----------
function startDetectionLoop() {
    const video = document.getElementById('camera-feed');
    if (!video) return;

    detectionInterval = setInterval(async () => {
        if (!isDetecting || video.readyState < 2) return;

        try {
            const bitmap = await createImageBitmap(video);
            worker.postMessage({ type: 'detect', image: bitmap }, [bitmap]);
        } catch (err) {
            // Ignore frame capture errors
        }
    }, DETECTION_INTERVAL_MS);
}

// ---------- Handle Live Detections ----------
function handleLiveDetection(data) {
    const { detections } = data;
    drawOverlay(detections);

    if (!detections || detections.length === 0) return;

    // Auto-save logic: confidence > threshold + cooldown
    const best = detections.reduce((a, b) => (a.score > b.score ? a : b));
    if (best.score >= CONFIDENCE_THRESHOLD) {
        const now = Date.now();
        if (now - lastSaveTime > SAVE_COOLDOWN) {
            lastSaveTime = now;
            autoSaveReport(best);
        }
    }
}

// ---------- Draw Overlay ----------
function drawOverlay(detections) {
    const canvas = document.getElementById('live-canvas');
    const video = document.getElementById('camera-feed');
    if (!canvas || !video) return;

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    if (!detections) return;

    detections.forEach((det) => {
        const [x, y, w, h] = det.bbox;

        // Box
        ctx.strokeStyle = '#22c55e';
        ctx.lineWidth = 3;
        ctx.strokeRect(x, y, w, h);

        // Label background
        ctx.fillStyle = '#22c55e';
        const label = `${det.label} ${(det.score * 100).toFixed(0)}%`;
        ctx.font = 'bold 14px Inter';
        const tw = ctx.measureText(label).width;
        ctx.fillRect(x, y - 22, tw + 8, 22);

        // Label text
        ctx.fillStyle = '#fff';
        ctx.fillText(label, x + 4, y - 6);
    });
}

// ---------- Auto-Save Report ----------
async function autoSaveReport(detection) {
    const user = auth.currentUser;
    if (!user) return;

    // Get current location
    let gps = null;
    try {
        const pos = await new Promise((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(resolve, reject, {
                enableHighAccuracy: true,
                timeout: 5000,
            });
        });
        gps = { lat: pos.coords.latitude, lng: pos.coords.longitude };
    } catch {
        console.warn('[Live] Could not get GPS for auto-save');
        return;
    }

    try {
        // Reverse geocode
        let address = '';
        if (window.google) {
            try {
                const geocoder = new google.maps.Geocoder();
                const res = await geocoder.geocode({ location: gps });
                if (res.results?.[0]) address = res.results[0].formatted_address;
            } catch { /* continue without address */ }
        }

        // Save to Firestore
        const now = new Date();
        const dd = String(now.getDate()).padStart(2, '0');
        const mm = String(now.getMonth() + 1).padStart(2, '0');
        const yy = String(now.getFullYear()).slice(-2);
        const hh = String(now.getHours()).padStart(2, '0');
        const min = String(now.getMinutes()).padStart(2, '0');
        const formattedDate = `${dd}/${mm}/${yy} ${hh}:${min}`;

        const counterRef = doc(db, 'metadata', 'reportCounter');
        const newReportRef = doc(collection(db, 'reports'));

        await runTransaction(db, async (transaction) => {
            const counterDoc = await transaction.get(counterRef);
            let nextId = 1;
            if (counterDoc.exists()) {
                nextId = (counterDoc.data().count || 0) + 1;
            }
            transaction.set(counterRef, { count: nextId });
            transaction.set(newReportRef, {
                id: nextId,
                hazardType: detection.label,
                date: formattedDate,
                coordinate: new GeoPoint(gps.lat, gps.lng),
                address,
                imageUrl: '', // TODO: Add image storage solution
                reportedBy: user.displayName || user.email || 'Unknown User',
                status: 'new',
            });
        });

        showToast(`Auto-saved: ${detection.label}`, 'success');
    } catch (err) {
        console.error('[Live] Auto-save error:', err);
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
});

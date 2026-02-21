// ============================================
// Live Detection Module (Camera + Real-time)
// ============================================

import { auth, db } from '../firebase-config.js';
import { showToast } from './app.js';
import { uploadToCloudinary } from './upload.js';
import {
    collection,
    doc,
    runTransaction,
    GeoPoint
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';

let worker = null;
let videoStream = null;
let isDetecting = false;
let isModelReady = false;
let detectionInterval = null;
let tracker = null;

const CONFIDENCE_THRESHOLD = 0.45;
const DETECTION_INTERVAL_MS = 250; // ~4 FPS inference

export function init() {
    setupWorker();
    setupCamera();
    setupControls();
    tracker = new HazardTracker();
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
    const video = document.getElementById('camera-feed');

    // Pass detections into the tracker
    const activeTracks = tracker.update(detections, video);

    // Draw tracking boxes
    drawOverlay(activeTracks);
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
        const [x, y, w, h] = track.bbox;

        // Box
        ctx.strokeStyle = '#22c55e';
        ctx.lineWidth = 3;
        ctx.strokeRect(x, y, w, h);

        // Label background
        ctx.fillStyle = '#22c55e';
        const label = `${track.label} (ID: ${track.id})`;
        ctx.font = 'bold 14px Inter';
        const tw = ctx.measureText(label).width;
        ctx.fillRect(x, y - 22, tw + 8, 22);

        // Label text
        ctx.fillStyle = '#fff';
        ctx.fillText(label, x + 4, y - 6);
    });
}

// ---------- Object Tracking (IoU) ----------
class HazardTracker {
    constructor() {
        this.tracks = [];
        this.nextId = 1;
        this.MAX_AGE = 5; // Frames to keep without seeing it
        this.MIN_HITS = 2; // Frames seen before it's considered valid
        this.IOU_THRESHOLD = 0.3; // Overlap required to match
    }

    update(detections, videoElement) {
        // Increment age of all tracks
        this.tracks.forEach(t => t.age++);

        // Match detections to existing tracks
        const matchedDetections = new Set();

        for (let track of this.tracks) {
            let bestIoU = 0;
            let bestDetIdx = -1;

            for (let i = 0; i < detections.length; i++) {
                if (matchedDetections.has(i)) continue;
                if (detections[i].label !== track.label) continue;

                const iou = this.calculateIoU(track.bbox, detections[i].bbox);
                if (iou > bestIoU && iou > this.IOU_THRESHOLD) {
                    bestIoU = iou;
                    bestDetIdx = i;
                }
            }

            if (bestDetIdx !== -1) {
                const det = detections[bestDetIdx];
                track.bbox = det.bbox;
                track.age = 0; // Reset age since we saw it
                track.hits++;

                // Keep the clearest frame
                if (det.score > track.bestScore) {
                    track.bestScore = det.score;
                    track.bestFrameCanvas = this.captureFrameCanvas(videoElement, track);
                }
                matchedDetections.add(bestDetIdx);
            }
        }

        // Create new tracks 
        for (let i = 0; i < detections.length; i++) {
            if (!matchedDetections.has(i)) {
                const det = detections[i];
                if (det.score >= CONFIDENCE_THRESHOLD) {
                    const newTrack = {
                        id: this.nextId++,
                        label: det.label,
                        bbox: det.bbox,
                        age: 0,
                        hits: 1,
                        bestScore: det.score,
                        saved: false
                    };
                    newTrack.bestFrameCanvas = this.captureFrameCanvas(videoElement, newTrack);
                    this.tracks.push(newTrack);
                }
            }
        }

        // Process mature/lost tracks
        const activeTracks = [];
        for (let track of this.tracks) {
            // Save if it's stable and we just lost track of it slightly
            // This ensures we have the best frame before saving.
            if (track.hits >= this.MIN_HITS && !track.saved && track.age === 1) {
                track.saved = true;
                autoSaveReport(track);
            }

            // Keep if not too old
            if (track.age < this.MAX_AGE) {
                activeTracks.push(track);
            }
        }

        this.tracks = activeTracks;
        return this.tracks.filter(t => t.hits >= 1 && t.age < 2);
    }

    calculateIoU(box1, box2) {
        const [x1, y1, w1, h1] = box1;
        const [x2, y2, w2, h2] = box2;

        const xA = Math.max(x1, x2);
        const yA = Math.max(y1, y2);
        const xB = Math.min(x1 + w1, x2 + w2);
        const yB = Math.min(y1 + h1, y2 + h2);

        const interArea = Math.max(0, xB - xA) * Math.max(0, yB - yA);
        const box1Area = w1 * h1;
        const box2Area = w2 * h2;
        const iou = interArea / parseFloat(box1Area + box2Area - interArea);

        return iou;
    }

    captureFrameCanvas(video, trackInfo) {
        try {
            const canvas = document.createElement('canvas');
            canvas.width = video.videoWidth;
            canvas.height = video.videoHeight;
            const ctx = canvas.getContext('2d');
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

            if (trackInfo) {
                const [x, y, w, h] = trackInfo.bbox;

                // Draw Box
                ctx.strokeStyle = '#22c55e';
                ctx.lineWidth = 3;
                ctx.strokeRect(x, y, w, h);

                // Draw Label Background
                ctx.fillStyle = '#22c55e';
                const label = `${trackInfo.label} ${(trackInfo.bestScore * 100).toFixed(0)}%`;
                ctx.font = 'bold 14px Inter';
                const tw = ctx.measureText(label).width;
                ctx.fillRect(x, y - 22, tw + 8, 22);

                // Draw Label Text
                ctx.fillStyle = '#fff';
                ctx.fillText(label, x + 4, y - 6);
            }

            return canvas;
        } catch (e) {
            return null;
        }
    }
}

// ---------- Auto-Save Report ----------
async function autoSaveReport(track) {
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

        // Upload image if we have it
        let imageUrl = '';
        if (track.bestFrameCanvas) {
            try {
                const blob = await new Promise(resolve => track.bestFrameCanvas.toBlob(resolve, 'image/jpeg', 0.8));
                if (blob) {
                    imageUrl = await uploadToCloudinary(blob, `hazard_live_${Date.now()}.jpg`);
                }
            } catch (blurErr) {
                console.warn('[Live] Image upload failed', blurErr);
            }
        }

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
                hazardType: track.label,
                date: formattedDate,
                coordinate: new GeoPoint(gps.lat, gps.lng),
                address,
                imageUrl: imageUrl,
                reportedBy: user.displayName || user.email || 'Unknown User',
                status: 'new',
            });
        });

        showToast(`Auto-saved: ${track.label} (ID: ${track.id})`, 'success');
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

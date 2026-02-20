// ============================================
// Image Upload & Static Detection Module
// ============================================

import { auth, db } from '../firebase-config.js';
import { showToast } from './app.js';
import {
    collection,
    addDoc,
    serverTimestamp
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';

let worker = null;
let currentGPS = null;
let detectionResult = null;
let currentFile = null;
let modelReady = false; // Track if worker model is loaded

export function init() {
    setupWorker();
    setupUpload();
}

// ---------- Web Worker ----------
function setupWorker() {
    if (worker) worker.terminate();
    worker = new Worker('js/worker.js');

    worker.onmessage = (e) => {
        const { type, data } = e.data;

        switch (type) {
            case 'model-loaded':
                console.log('[Upload] Model loaded in worker');
                modelReady = true;
                break;

            case 'detection-result':
                handleDetectionResult(data);
                break;

            case 'error':
                console.error('[Upload] Worker error:', data);
                showToast('Detection failed', 'error');
                hideLoading();
                break;
        }
    };

    worker.postMessage({ type: 'load-model' });
}

// ---------- File Upload ----------
function setupUpload() {
    const fileInput = document.getElementById('file-input');
    const uploadArea = document.getElementById('upload-area');
    const saveBtn = document.getElementById('save-report-btn');

    if (uploadArea) {
        uploadArea.addEventListener('click', () => fileInput?.click());

        // Drag & Drop
        uploadArea.addEventListener('dragover', (e) => {
            e.preventDefault();
            uploadArea.classList.add('border-primary-500');
        });
        uploadArea.addEventListener('dragleave', () => {
            uploadArea.classList.remove('border-primary-500');
        });
        uploadArea.addEventListener('drop', (e) => {
            e.preventDefault();
            uploadArea.classList.remove('border-primary-500');
            if (e.dataTransfer.files.length > 0) {
                handleFile(e.dataTransfer.files[0]);
            }
        });
    }

    if (fileInput) {
        fileInput.addEventListener('change', (e) => {
            if (e.target.files.length > 0) {
                handleFile(e.target.files[0]);
            }
        });
    }

    if (saveBtn) {
        saveBtn.addEventListener('click', saveReport);
    }
}

// ---------- Process File ----------
async function handleFile(file) {
    if (!file.type.startsWith('image/')) {
        showToast('Please upload an image file', 'error');
        return;
    }

    // Reset state
    detectionResult = null;
    currentGPS = null;
    currentFile = file;
    hideSaveButton();
    showLoading();
    const locationContainer = document.getElementById('location-container');
    if (locationContainer) locationContainer.classList.add('hidden');
    const addressEl = document.getElementById('detected-address');
    if (addressEl) addressEl.textContent = 'Waiting for image...';

    // Display preview
    const preview = document.getElementById('image-preview');
    const img = new Image();

    img.onload = async () => {
        if (preview) {
            preview.src = img.src;
            preview.classList.remove('hidden');
            const locationContainer = document.getElementById('location-container');
            if (locationContainer) locationContainer.classList.remove('hidden');
        }

        // Extract EXIF GPS using exif-js
        await extractGPS(file);

        // Wait for model if not ready
        if (!modelReady) {
            console.log('[Upload] Model not ready, waiting...');
            showToast('Loading AI model...', 'info');
            // We could naturally wait for the model-loaded event, but for now simple check
        }

        // Send to worker for detection
        const bitmap = await createImageBitmap(img);
        worker.postMessage({ type: 'detect', image: bitmap }, [bitmap]);
    };

    img.src = URL.createObjectURL(file);
}

// ---------- GPS Extraction (exif-js) ----------
async function extractGPS(file) {
    return new Promise((resolve) => {
        console.log('[Upload] Starting GPS extraction for:', file.name);
        if (typeof EXIF === 'undefined') {
            console.warn('[Upload] EXIF library not loaded, falling back to geolocation');
            fallbackToGeolocation().then(resolve);
            return;
        }

        EXIF.getData(file, function () {
            const allTags = EXIF.getAllTags(this);
            console.log('[Upload] All EXIF tags found:', Object.keys(allTags));

            const lat = EXIF.getTag(this, 'GPSLatitude');
            const lng = EXIF.getTag(this, 'GPSLongitude');
            const latRef = EXIF.getTag(this, 'GPSLatitudeRef');
            const lngRef = EXIF.getTag(this, 'GPSLongitudeRef');

            if (lat && lng) {
                console.log('[Upload] Raw GPS data found:', { lat, lng, latRef, lngRef });
                try {
                    const latitude = convertDMSToDD(lat, latRef);
                    const longitude = convertDMSToDD(lng, lngRef);
                    currentGPS = { lat: latitude, lng: longitude };
                    console.log('[Upload] Successfully extracted GPS:', currentGPS);
                    reverseGeocode(latitude, longitude);
                    resolve();
                } catch (err) {
                    console.error('[Upload] Error converting DMS to DD:', err);
                    fallbackToGeolocation().then(resolve);
                }
            } else {
                console.warn('[Upload] No GPS tags found in EXIF');
                showToast('No GPS data in image. Using current location.', 'info');
                fallbackToGeolocation().then(resolve);
            }
        });
    });
}

function convertDMSToDD(dms, ref) {
    // Some devices return rational objects, others return arrays of numbers
    const parse = (val) => {
        if (typeof val === 'object' && val.numerator !== undefined) {
            return val.numerator / val.denominator;
        }
        return val;
    };

    const d = parse(dms[0]);
    const m = parse(dms[1]);
    const s = parse(dms[2]);

    const dd = d + m / 60 + s / 3600;
    return (ref === 'S' || ref === 'W') ? -dd : dd;
}


async function fallbackToGeolocation() {
    if (!navigator.geolocation) {
        showToast('Location not available', 'error');
        return;
    }

    return new Promise((resolve) => {
        navigator.geolocation.getCurrentPosition(
            (pos) => {
                currentGPS = { lat: pos.coords.latitude, lng: pos.coords.longitude };
                reverseGeocode(currentGPS.lat, currentGPS.lng);
                resolve();
            },
            () => {
                showToast('Could not get location. Report cannot be saved.', 'error');
                resolve();
            },
            { enableHighAccuracy: true, timeout: 10000 }
        );
    });
}

// ---------- Reverse Geocoding ----------
function reverseGeocode(lat, lng) {
    if (!window.google) return;
    const geocoder = new google.maps.Geocoder();

    geocoder.geocode({ location: { lat, lng } }, (results, status) => {
        if (status === 'OK' && results && results[0]) {
            console.log('[Upload] Reverse geocode result:', results[0].formatted_address);
            const addressEl = document.getElementById('detected-address');
            if (addressEl) addressEl.textContent = results[0].formatted_address;
            currentGPS.address = results[0].formatted_address;
        } else {
            console.warn('[Upload] Geocoder failed due to:', status);
        }
    });
}

// ---------- Detection Result Handler ----------
function handleDetectionResult(data) {
    hideLoading();
    const { detections } = data;
    const resultEl = document.getElementById('detection-result');

    if (detections && detections.length > 0) {
        detectionResult = detections[0]; // Best detection
        drawBoundingBoxes(detections);

        if (resultEl) {
            resultEl.innerHTML = `
        <div class="flex items-center gap-2 text-success">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          <span class="font-semibold">${detectionResult.label}</span>
          <span class="text-dark-400 text-sm">(${(detectionResult.score * 100).toFixed(1)}%)</span>
        </div>`;
        }

        // Show save button if GPS is also present
        if (currentGPS) showSaveButton();
    } else {
        if (resultEl) {
            resultEl.innerHTML = `
        <p class="text-dark-400">No hazard detected in this image.</p>`;
        }
    }
}

// ---------- Draw Bounding Boxes ----------
function drawBoundingBoxes(detections) {
    const canvas = document.getElementById('detection-canvas');
    const preview = document.getElementById('image-preview');
    if (!canvas || !preview) return;

    canvas.width = preview.naturalWidth;
    canvas.height = preview.naturalHeight;
    const ctx = canvas.getContext('2d');

    detections.forEach((det) => {
        const [x, y, w, h] = det.bbox;
        ctx.strokeStyle = '#22c55e';
        ctx.lineWidth = 3;
        ctx.strokeRect(x, y, w, h);

        // Label
        ctx.fillStyle = '#22c55e';
        ctx.font = 'bold 14px Inter';
        const label = `${det.label} ${(det.score * 100).toFixed(0)}%`;
        const textWidth = ctx.measureText(label).width;
        ctx.fillRect(x, y - 22, textWidth + 8, 22);
        ctx.fillStyle = '#fff';
        ctx.fillText(label, x + 4, y - 6);
    });
}

// ---------- Save Report ----------
async function saveReport() {
    if (!detectionResult || !currentGPS) {
        showToast('Cannot save: missing detection or GPS data', 'error');
        return;
    }

    const user = auth.currentUser;
    if (!user) {
        showToast('Please sign in', 'error');
        return;
    }

    const saveBtn = document.getElementById('save-report-btn');
    if (saveBtn) {
        saveBtn.disabled = true;
        saveBtn.innerHTML = '<div class="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div>';
    }

    try {
        // Save to Firestore (image URL will be handled separately when storage is configured)
        await addDoc(collection(db, 'reports'), {
            hazardType: detectionResult.label,
            date: serverTimestamp(),
            coordinate: { lat: currentGPS.lat, lng: currentGPS.lng },
            address: currentGPS.address || '',
            imageUrl: '', // TODO: Add image storage solution
            reportedBy: user.uid,
            status: 'open',
        });

        showToast('Report saved successfully!', 'success');
        hideSaveButton();
    } catch (err) {
        console.error('[Upload] Save error:', err);
        showToast('Failed to save report', 'error');
    } finally {
        if (saveBtn) {
            saveBtn.disabled = false;
            saveBtn.innerHTML = '💾 Save Report';
        }
    }
}

// ---------- UI Helpers ----------
function showLoading() {
    const el = document.getElementById('detection-loading');
    if (el) el.classList.remove('hidden');
}

function hideLoading() {
    const el = document.getElementById('detection-loading');
    if (el) el.classList.add('hidden');
}

function showSaveButton() {
    const btn = document.getElementById('save-report-btn');
    if (btn) btn.classList.remove('hidden');
}

function hideSaveButton() {
    const btn = document.getElementById('save-report-btn');
    if (btn) btn.classList.add('hidden');
}

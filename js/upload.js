// ============================================
// Image Upload & Static Detection Module
// ============================================

import { auth, db, firebaseConfig } from '../firebase-config.js';
import { showToast } from './app.js';
import {
    collection,
    doc,
    runTransaction,
    GeoPoint
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

    // Clear previous canvas drawing
    const canvas = document.getElementById('detection-canvas');
    if (canvas) {
        const ctx = canvas.getContext('2d');
        ctx.clearRect(0, 0, canvas.width, canvas.height);
    }

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
            console.warn('[Upload] EXIF library not loaded, cannot extract GPS');
            showToast('EXIF library missing. Cannot read location.', 'error');
            resolve();
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
                    showToast('Failed to parse GPS data from image.', 'error');
                    resolve();
                }
            } else {
                console.warn('[Upload] No GPS tags found in EXIF');
                showToast('No GPS data found in image. Location required.', 'error');
                resolve();
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




// ---------- Reverse Geocoding ----------
async function reverseGeocode(lat, lng) {
    try {
        const apiKey = firebaseConfig.apiKey; // Using Firebase config's Google API key, or ENV if available
        const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${apiKey}`;

        const response = await fetch(url);
        const data = await response.json();

        if (data.status === 'OK' && data.results && data.results.length > 0) {
            const formattedAddress = data.results[0].formatted_address;
            console.log('[Upload] Reverse geocode result:', formattedAddress);

            const addressEl = document.getElementById('detected-address');
            if (addressEl) addressEl.textContent = formattedAddress;

            if (currentGPS) currentGPS.address = formattedAddress;
        } else if (data.status === 'REQUEST_DENIED') {
            console.warn('[Upload] Geocoder failed due to: REQUEST_DENIED. Check API Key restrictions or billing.');
            const addressEl = document.getElementById('detected-address');
            if (addressEl) addressEl.textContent = 'Location address unavailable (API Key Issue)';
            if (currentGPS) currentGPS.address = 'Location address unavailable';
        } else {
            console.warn('[Upload] Geocoder failed due to:', data.status);
            const addressEl = document.getElementById('detected-address');
            if (addressEl) addressEl.textContent = 'Location address unavailable';
        }
    } catch (err) {
        console.error('[Upload] Geocoding fetch error:', err);
    }
}

// ---------- Detection Result Handler ----------
function handleDetectionResult(data) {
    hideLoading();
    const { detections } = data;
    const resultEl = document.getElementById('detection-result');

    if (detections && detections.length > 0) {
        const uniqueLabels = [...new Set(detections.map(d => d.label))].join(', ');
        detectionResult = { ...detections[0], label: uniqueLabels }; // Store combined labels for saving

        drawBoundingBoxes(detections); // Uses original detections array for boxes

        if (resultEl) {
            resultEl.innerHTML = `
        <div class="flex items-center gap-2 text-success">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
          </svg>
          <span class="font-semibold">${uniqueLabels}</span>
        </div>`;
        }

        showSaveButton();
        const btn = document.getElementById('save-report-btn');
        if (btn) {
            if (!currentGPS) {
                btn.classList.add('opacity-50', 'cursor-not-allowed');
                btn.title = "Cannot save image without location data. Please enable location permissions in your camera next time.";
            } else {
                btn.classList.remove('opacity-50', 'cursor-not-allowed');
                btn.title = "";
            }
        }
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

    // Dynamically scale line width and font size for large images
    const scaleFactor = Math.max(preview.naturalWidth / 600, 1);

    detections.forEach((det) => {
        const [x, y, w, h] = det.bbox;
        ctx.strokeStyle = '#22c55e';
        ctx.lineWidth = 4 * scaleFactor;
        ctx.strokeRect(x, y, w, h);

        // Label
        ctx.fillStyle = '#22c55e';
        const fontSize = Math.floor(16 * scaleFactor);
        ctx.font = `bold ${fontSize}px Inter`;
        const label = `${det.label} ${(det.score * 100).toFixed(0)}%`;
        const textWidth = ctx.measureText(label).width;

        const padX = 8 * scaleFactor;
        const padY = 6 * scaleFactor;
        const boxHeight = fontSize + padY * 2;

        ctx.fillRect(x, y - boxHeight, textWidth + padX * 2, boxHeight);
        ctx.fillStyle = '#fff';
        ctx.fillText(label, x + padX, y - padY);
    });
}

async function uploadToCloudinary(blob, filename = 'hazard.jpg') {
    const cloudName = window.ENV?.CLOUDINARY_CLOUD_NAME;
    const uploadPreset = window.ENV?.CLOUDINARY_UPLOAD_PRESET;

    if (!cloudName || !uploadPreset) {
        throw new Error('Cloudinary config missing in .env file');
    }

    const url = `https://api.cloudinary.com/v1_1/${cloudName}/image/upload`;
    const formData = new FormData();
    formData.append('file', blob, filename);
    formData.append('upload_preset', uploadPreset);

    const response = await fetch(url, {
        method: 'POST',
        body: formData
    });

    if (!response.ok) {
        throw new Error('Failed to upload image to Cloudinary');
    }

    const data = await response.json();
    return data.secure_url;
}

// Helper to get image + bounding boxes as a single Blob
async function getCombinedCanvasBlob() {
    return new Promise((resolve, reject) => {
        const preview = document.getElementById('image-preview');
        const overlayCanvas = document.getElementById('detection-canvas');

        if (!preview || !overlayCanvas) {
            reject(new Error('Missing image preview or canvas'));
            return;
        }

        // Create an offscreen canvas to merge them
        const mergedCanvas = document.createElement('canvas');
        mergedCanvas.width = preview.naturalWidth;
        mergedCanvas.height = preview.naturalHeight;
        const ctx = mergedCanvas.getContext('2d');

        // Draw original image first
        ctx.drawImage(preview, 0, 0, mergedCanvas.width, mergedCanvas.height);

        // Draw the overlay canvas (which contains the green boxes) on top
        // Note: overlayCanvas is already sized to naturalWidth/Height in drawBoundingBoxes
        ctx.drawImage(overlayCanvas, 0, 0);

        // Convert to highly compact JPEG blob
        mergedCanvas.toBlob(
            (blob) => {
                if (blob) resolve(blob);
                else reject(new Error('Failed to create blob from canvas'));
            },
            'image/jpeg',
            0.85
        );
    });
}

// ---------- Save Report ----------
async function saveReport() {
    if (!detectionResult) {
        showToast('Cannot save: missing detection data', 'error');
        return;
    }
    if (!currentGPS) {
        showToast('Cannot save image without location data. Please enable location permissions in your camera next time.', 'error');
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
        // Create canvas blob and upload to Cloudinary
        showToast('Uploading image with detection...', 'info');
        const combinedBlob = await getCombinedCanvasBlob();
        const uploadedImageUrl = await uploadToCloudinary(combinedBlob, currentFile.name);

        const now = new Date();
        const dd = String(now.getDate()).padStart(2, '0');
        const mm = String(now.getMonth() + 1).padStart(2, '0');
        const yy = String(now.getFullYear()).slice(-2);
        const hh = String(now.getHours()).padStart(2, '0');
        const min = String(now.getMinutes()).padStart(2, '0');
        const formattedDate = `${dd}/${mm}/${yy} ${hh}:${min}`;

        // Save to Firestore with auto-incremented ID
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
                hazardType: detectionResult.label,
                date: formattedDate,
                coordinate: new GeoPoint(currentGPS.lat, currentGPS.lng),
                address: currentGPS.address || '',
                imageUrl: uploadedImageUrl,
                reportedBy: user.displayName || user.email || 'Unknown User',
                status: 'new',
            });
        });

        showToast('Report saved successfully!', 'success');
        hideSaveButton();

        // Clear UI after 5 seconds
        setTimeout(() => {
            const preview = document.getElementById('image-preview');
            const canvas = document.getElementById('detection-canvas');
            const resultEl = document.getElementById('detection-result');
            const addressEl = document.getElementById('detected-address');

            if (preview) {
                preview.src = '';
                preview.classList.add('hidden');
            }
            if (canvas) {
                const ctx = canvas.getContext('2d');
                ctx.clearRect(0, 0, canvas.width, canvas.height);
            }
            if (resultEl) resultEl.innerHTML = '';
            if (addressEl) addressEl.textContent = 'Waiting for image...';

            // Reset location container visibility
            const locationContainer = document.getElementById('location-container');
            if (locationContainer) locationContainer.classList.add('hidden');

            currentFile = null;
            detectionResult = null;
            currentGPS = null;
        }, 5000);
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

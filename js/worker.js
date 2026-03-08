// ============================================
// TensorFlow.js Web Worker - Hazard Detection
// ============================================
// This worker runs in a separate thread to keep
// the main UI thread smooth at 60 FPS.

importScripts('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.17.0/dist/tf.min.js');

let model = null;
let currentModelType = null; // 'live' or 'static'
const MODEL_PATH_LIVE = '/assets/models/YOLO12n/model.json';
const MODEL_PATH_STATIC = '/assets/models/YOLO26n/model.json';
const LABELS = ['Crack', 'Pothole']; // Swapped Crack and Pothole
const NMS_IOU_THRESHOLD = 0.5;
const NMS_SCORE_THRESHOLD = 0.45;

// ---------- Message Handler ----------
self.onmessage = async (e) => {
    const { type, image, speed } = e.data;

    switch (type) {
        case 'load-model':
            await loadModel(e.data.target);
            break;

        case 'detect':
            if (!model) {
                self.postMessage({ type: 'error', data: 'Model not loaded' });
                try { image.close(); } catch (err) { }
                return;
            }
            await runDetection(image, speed || 0);
            break;

        case 'detect-static':
            if (!model) {
                self.postMessage({ type: 'error', data: 'Model not loaded' });
                try { image.close(); } catch (err) { }
                return;
            }
            await runStaticDetection(image);
            break;
    }
};

// ---------- Load Model ----------
async function loadModel(target) {
    try {
        if (model && currentModelType === target) {
            self.postMessage({ type: 'model-loaded', data: { success: true, target } });
            return;
        }

        self.postMessage({ type: 'status', data: `Loading ${target} model...` });

        currentModelType = target;
        const modelPath = target === 'live' ? MODEL_PATH_LIVE : MODEL_PATH_STATIC;

        // Load the custom TensorFlow.js model
        // Supports: tf.loadGraphModel (converted SavedModel/frozen) or tf.loadLayersModel (Keras)
        model = await tf.loadGraphModel(modelPath);

        console.log(`[Worker] Model ${target} loaded successfully from ${modelPath}`);
        self.postMessage({ type: 'model-loaded', data: { success: true, target } });
    } catch (err) {
        console.error('[Worker] Model load error:', err);
        self.postMessage({ type: 'error', data: `Failed to load model: ${err.message}` });
    }
}

// ---------- Tracking State Machine ----------
const TrackState = {
    TENTATIVE: 'tentative',
    CONFIRMED: 'confirmed',
    VANISHED: 'vanished',
    REPORTED: 'reported',
    DELETED: 'deleted'
};

class TrackManager {
    constructor() {
        this.tracks = [];
        this.nextId = 1;
        this.IOU_THRESHOLD = 0.3;
        this.MIN_HITS = 1;       // Required frames to confirm (reduced for snappier response)
        this.MAX_AGE = 15;       // Grace period before disappearing (handling occlusion)
    }

    update(detections, currentImageBitmap, speed = 0) {
        let requiredHits = this.MIN_HITS;
        let confThreshold = NMS_SCORE_THRESHOLD;

        // Adaptive Confidence (Step 3): > 50km/h = ~13.8 m/s
        if (speed > 13.8) {
            confThreshold = 0.35; // Catch blurred objects, but bounded slightly higher than before (was 0.35)
            requiredHits = 1;     // Require LESS frames to be confirmed since objects pass quickly
        }

        // Increment age
        this.tracks.forEach(t => {
            if (t.state !== TrackState.REPORTED) t.age++;
        });

        const matchedDetections = new Set();
        let keepBitmap = false;

        // Match existing tracks
        for (let track of this.tracks) {
            if (track.state === TrackState.REPORTED) continue;

            let bestIoU = 0;
            let bestDetIdx = -1;

            for (let i = 0; i < detections.length; i++) {
                if (matchedDetections.has(i)) continue;
                if (detections[i].label !== track.label) continue;
                if (detections[i].score < confThreshold) continue;

                const iou = this.calculateIoU(track.bbox, detections[i].bbox);
                if (iou > bestIoU && iou > this.IOU_THRESHOLD) {
                    bestIoU = iou;
                    bestDetIdx = i;
                }
            }

            if (bestDetIdx !== -1) {
                const det = detections[bestDetIdx];

                // Velocity Prediction (Step 3) - compute displacement
                track.vx = det.bbox[0] - track.bbox[0];
                track.vy = det.bbox[1] - track.bbox[1];

                track.bbox = det.bbox;
                track.age = 0;
                track.hits++;

                if (track.state === TrackState.TENTATIVE && track.hits >= requiredHits) {
                    track.state = TrackState.CONFIRMED;
                } else if (track.state === TrackState.VANISHED) {
                    track.state = TrackState.CONFIRMED;
                }

                // Golden Frame Buffer (Step 4)
                const area = det.bbox[2] * det.bbox[3];
                const frameScore = det.score * area;
                track.frameBuffer.push({ score: frameScore, bitmap: currentImageBitmap, bbox: det.bbox, scoreRaw: det.score });
                track.frameBuffer.sort((a, b) => b.score - a.score); // Highest first
                keepBitmap = true;

                if (track.frameBuffer.length > 5) {
                    const toDiscard = track.frameBuffer.pop();
                    if (toDiscard && toDiscard.bitmap !== currentImageBitmap && !this.isBitmapUsed(toDiscard.bitmap, track)) {
                        try { toDiscard.bitmap.close(); } catch (e) { }
                    }
                }

                matchedDetections.add(bestDetIdx);
            } else {
                if (track.state === TrackState.CONFIRMED) {
                    track.state = TrackState.VANISHED;
                }
            }
        }

        // Unmatched detections -> new tentative tracks
        for (let i = 0; i < detections.length; i++) {
            if (!matchedDetections.has(i)) {
                const det = detections[i];
                if (det.score >= confThreshold) {
                    const area = det.bbox[2] * det.bbox[3];
                    const frameScore = det.score * area;
                    const newTrack = {
                        id: this.nextId++,
                        label: det.label,
                        bbox: det.bbox,
                        vx: 0,
                        vy: 0,
                        age: 0,
                        hits: 1,
                        state: TrackState.TENTATIVE,
                        frameBuffer: [{ score: frameScore, bitmap: currentImageBitmap, bbox: det.bbox, scoreRaw: det.score }]
                    };
                    this.tracks.push(newTrack);
                    keepBitmap = true;
                }
            }
        }

        const activeTracks = [];
        const reportsTriggered = [];

        for (let track of this.tracks) {
            if (track.state === TrackState.REPORTED) continue;

            if (track.state === TrackState.VANISHED && track.age > this.MAX_AGE) {
                // Disappearance Trigger (Step 4): Needs to be in bottom third of frame
                // We use bbox y + h vs image height
                const imageHeight = currentImageBitmap.height;
                const [x, y, w, h] = track.bbox;
                if (y + h > imageHeight * 0.6) {
                    track.state = TrackState.REPORTED;
                    const bestFrame = track.frameBuffer[0];
                    reportsTriggered.push({
                        label: track.label,
                        score: bestFrame.scoreRaw,
                        bbox: bestFrame.bbox,
                        bitmap: bestFrame.bitmap
                    });
                    this.closeBitmapsExcept(track, bestFrame.bitmap);
                } else {
                    track.state = TrackState.DELETED;
                    this.closeBitmapsExcept(track, null);
                }
            } else if (track.state === TrackState.TENTATIVE && track.age > 2) {
                track.state = TrackState.DELETED;
                this.closeBitmapsExcept(track, null);
            }

            if (track.state !== TrackState.DELETED && track.state !== TrackState.REPORTED) {
                // Velocity Prediction correction
                let predictedBbox = [...track.bbox];
                if (track.age > 0) {
                    predictedBbox[0] += track.vx * track.age;
                    predictedBbox[1] += track.vy * track.age;
                }
                activeTracks.push({
                    id: track.id,
                    label: track.label,
                    bbox: predictedBbox,
                    state: track.state,
                    age: track.age,
                    hits: track.hits
                });
            }
        }

        this.tracks = this.tracks.filter(t => t.state !== TrackState.DELETED && t.state !== TrackState.REPORTED);
        return { activeTracks, reportsTriggered, keepBitmap };
    }

    isBitmapUsed(bitmap, skipTrack) {
        for (let t of this.tracks) {
            if (t === skipTrack) continue;
            for (let f of t.frameBuffer || []) {
                if (f.bitmap === bitmap) return true;
            }
        }
        return false;
    }

    closeBitmapsExcept(track, keepBitmap) {
        for (let f of track.frameBuffer || []) {
            if (f.bitmap && f.bitmap !== keepBitmap && !this.isBitmapUsed(f.bitmap, track)) {
                try { f.bitmap.close(); } catch (e) { }
            }
        }
        track.frameBuffer = track.frameBuffer ? track.frameBuffer.filter(f => f.bitmap === keepBitmap) : [];
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
}

const tracker = new TrackManager();

// ---------- Run Detection ----------
async function runDetection(imageBitmap, speed) {
    let keepBitmap = false;
    try {
        let activeTracks, reportsTriggered;
        let filtered = [];

        tf.engine().startScope();
        try {
            // Convert ImageBitmap to tensor
            const tensor = tf.browser.fromPixels(imageBitmap);
            const [height, width] = tensor.shape;

            // Preprocess: resize to model input size and normalize
            const inputSize = 640; // Adjust based on your model
            const resized = tf.image.resizeBilinear(tensor, [inputSize, inputSize]);
            const normalized = resized.div(255.0);
            const batched = normalized.expandDims(0);

            // Run inference
            const predictions = await model.predict(batched);

            if (currentModelType === 'live') {
                // Parse results for YOLO12n (v8 format) which requires NMS
                const rawDetections = await parseDetectionsV8(predictions, width, height);
                filtered = await applyNMS(rawDetections);
            } else {
                // Parse results for YOLO26n (End-to-End model, no NMS required)
                filtered = await parseDetections(predictions, width, height);
            }
        } finally {
            tf.engine().endScope();
        }

        // Send results to TrackManager
        const result = tracker.update(filtered, imageBitmap, speed);
        activeTracks = result.activeTracks;
        reportsTriggered = result.reportsTriggered;
        keepBitmap = result.keepBitmap;

        // Send active tracks to UI
        self.postMessage({
            type: 'detection-result',
            data: { activeTracks },
        });

        // Send triggers
        if (reportsTriggered.length > 0) {
            self.postMessage({
                type: 'report-hazard',
                data: reportsTriggered,
            }, reportsTriggered.map(r => r.bitmap)); // transfer the ImageBitmaps
        }
        // Close the ImageBitmap if not stored in buffer
        if (!keepBitmap) {
            try { imageBitmap.close(); } catch (e) { }
        }
    } catch (err) {
        console.error('[Worker] Detection error:', err);
        self.postMessage({ type: 'error', data: err.message });
        if (!keepBitmap) {
            try { imageBitmap.close(); } catch (e) { }
        }
    }
}

// ---------- Run Static Detection (Single Image) ----------
async function runStaticDetection(imageBitmap) {
    try {
        let filtered = [];

        tf.engine().startScope();
        try {
            const tensor = tf.browser.fromPixels(imageBitmap);
            const [height, width] = tensor.shape;

            const inputSize = 640;
            const resized = tf.image.resizeBilinear(tensor, [inputSize, inputSize]);
            const normalized = resized.div(255.0);
            const batched = normalized.expandDims(0);

            const predictions = await model.predict(batched);

            if (currentModelType === 'live') {
                const rawDetections = await parseDetectionsV8(predictions, width, height);
                filtered = await applyNMS(rawDetections);
            } else {
                filtered = await parseDetections(predictions, width, height);
            }
        } finally {
            tf.engine().endScope();
        }

        // For static detection, we just return the raw NMS filtered boxes without tracking
        self.postMessage({
            type: 'detection-result',
            data: { detections: filtered },
        });

        try { imageBitmap.close(); } catch (e) { }

    } catch (err) {
        console.error('[Worker] Static detection error:', err);
        self.postMessage({ type: 'error', data: err.message });
        try { imageBitmap.close(); } catch (e) { }
    }
}

// ---------- Parse Detections ----------
// YOLO output format for end-to-end (NMS-free) models: [1, 300, 6]
// where each row is: [x_min, y_min, x_max, y_max, score, class_id]
async function parseDetections(predictions, origWidth, origHeight) {
    const detections = [];

    // Extract the output tensor
    const outputTensor = Array.isArray(predictions) ? predictions[0] : predictions;

    // Squeeze the batch dimension: [1, 300, 6] -> [300, 6]
    const squeezed = outputTensor.squeeze([0]);
    const data = await squeezed.data();

    const numBoxes = squeezed.shape[0];

    for (let i = 0; i < numBoxes; i++) {
        const offset = i * 6;

        const score = data[offset + 4];
        if (score < NMS_SCORE_THRESHOLD) continue;

        const classId = Math.round(data[offset + 5]);

        // Output from YOLO TFJS is usually absolute coordinates relative to the input tensor (640)
        let xmin = data[offset];
        let ymin = data[offset + 1];
        let xmax = data[offset + 2];
        let ymax = data[offset + 3];

        // Normalize depending on the image dimensions scale
        const scaleX = origWidth / 640;
        const scaleY = origHeight / 640;

        detections.push({
            bbox: [
                xmin * scaleX,
                ymin * scaleY,
                (xmax - xmin) * scaleX,
                (ymax - ymin) * scaleY,
            ],
            score: score,
            label: LABELS[classId] || `Class ${classId}`,
            classId: classId,
        });
    }

    squeezed.dispose();
    return detections;
}

// YOLOv8/YOLO12 format for live model: [1, 6, 8400]
async function parseDetectionsV8(predictions, origWidth, origHeight) {
    const detections = [];

    // Extract the output tensor
    const outputTensor = Array.isArray(predictions) ? predictions[0] : predictions;

    // Squeeze the batch dimension and transpose from [6, 8400] to [8400, 6]
    // so each row is a single detection anchor prediction
    const squeezed = outputTensor.squeeze([0]);
    const transposed = squeezed.transpose([1, 0]);
    const data = await transposed.data();

    const numAnchors = transposed.shape[0]; // should be 8400
    const numFeatures = transposed.shape[1]; // should be 6
    const numClasses = numFeatures - 4; // 2 classes in this case

    for (let i = 0; i < numAnchors; i++) {
        const offset = i * numFeatures;

        // Find best class confidence
        let maxClassConf = -1;
        let classId = -1;
        for (let c = 0; c < numClasses; c++) {
            const conf = data[offset + 4 + c];
            if (conf > maxClassConf) {
                maxClassConf = conf;
                classId = c;
            }
        }

        // If below threshold, skip
        if (maxClassConf < NMS_SCORE_THRESHOLD) continue;

        const xCenter = data[offset];
        const yCenter = data[offset + 1];
        const w = data[offset + 2];
        const h = data[offset + 3];

        // Normalize coordinates (0-1) in case the model outputs 0-640 (tensor size)
        // Some models output normalized coordinates, others do not.
        const scaleX = xCenter > 1 ? 1 / 640 : 1;
        const scaleY = yCenter > 1 ? 1 / 640 : 1;
        const scaleW = w > 1 ? 1 / 640 : 1;
        const scaleH = h > 1 ? 1 / 640 : 1;

        const normX = xCenter * scaleX;
        const normY = yCenter * scaleY;
        const normW = w * scaleW;
        const normH = h * scaleH;

        // Convert normalized coordinates to pixel coordinates for the original image
        detections.push({
            bbox: [
                (normX - normW / 2) * origWidth,
                (normY - normH / 2) * origHeight,
                normW * origWidth,
                normH * origHeight,
            ],
            score: maxClassConf,
            label: LABELS[classId] || `Class ${classId}`,
            classId,
        });
    }

    squeezed.dispose();
    transposed.dispose();

    return detections;
}

// ---------- Non-Maximum Suppression ----------
async function applyNMS(detections) {
    if (detections.length === 0) return [];

    const boxes = detections.map((d) => [
        d.bbox[1], // y1
        d.bbox[0], // x1
        d.bbox[1] + d.bbox[3], // y2
        d.bbox[0] + d.bbox[2], // x2
    ]);
    const scores = detections.map((d) => d.score);

    const boxesTensor = tf.tensor2d(boxes);
    const scoresTensor = tf.tensor1d(scores);

    const nmsIndices = await tf.image.nonMaxSuppressionAsync(
        boxesTensor,
        scoresTensor,
        20, // max detections
        NMS_IOU_THRESHOLD,
        NMS_SCORE_THRESHOLD
    );

    const indices = await nmsIndices.data();
    const filtered = Array.from(indices).map((i) => detections[i]);

    boxesTensor.dispose();
    scoresTensor.dispose();
    nmsIndices.dispose();

    return filtered;
}

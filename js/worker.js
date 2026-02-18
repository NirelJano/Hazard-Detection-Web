// ============================================
// TensorFlow.js Web Worker - Hazard Detection
// ============================================
// This worker runs in a separate thread to keep
// the main UI thread smooth at 60 FPS.

importScripts('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.17.0/dist/tf.min.js');

let model = null;
const MODEL_PATH = 'assets/model/model.json'; // Path to your custom model
const LABELS = ['Pothole', 'Crack', 'Bump', 'Debris']; // Update with your model's labels
const NMS_IOU_THRESHOLD = 0.5;
const NMS_SCORE_THRESHOLD = 0.4;

// ---------- Message Handler ----------
self.onmessage = async (e) => {
    const { type, image } = e.data;

    switch (type) {
        case 'load-model':
            await loadModel();
            break;

        case 'detect':
            if (!model) {
                self.postMessage({ type: 'error', data: 'Model not loaded' });
                return;
            }
            await runDetection(image);
            break;
    }
};

// ---------- Load Model ----------
async function loadModel() {
    try {
        self.postMessage({ type: 'status', data: 'Loading model...' });

        // Load the custom TensorFlow.js model
        // Supports: tf.loadGraphModel (converted SavedModel/frozen) or tf.loadLayersModel (Keras)
        model = await tf.loadGraphModel(MODEL_PATH);

        console.log('[Worker] Model loaded successfully');
        self.postMessage({ type: 'model-loaded', data: { success: true } });
    } catch (err) {
        console.error('[Worker] Model load error:', err);
        self.postMessage({ type: 'error', data: `Failed to load model: ${err.message}` });
    }
}

// ---------- Run Detection ----------
async function runDetection(imageBitmap) {
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

        // Parse results (adjust based on your model's output format)
        const detections = await parseDetections(predictions, width, height);

        // Apply Non-Maximum Suppression
        const filtered = await applyNMS(detections);

        // Send results back to main thread
        self.postMessage({
            type: 'detection-result',
            data: { detections: filtered },
        });

        // Cleanup tensors
        tensor.dispose();
        resized.dispose();
        normalized.dispose();
        batched.dispose();
        if (Array.isArray(predictions)) {
            predictions.forEach((p) => p.dispose());
        } else {
            predictions.dispose();
        }

        // Close the ImageBitmap
        imageBitmap.close();
    } catch (err) {
        console.error('[Worker] Detection error:', err);
        self.postMessage({ type: 'error', data: err.message });
        imageBitmap.close();
    }
}

// ---------- Parse Detections ----------
// NOTE: This function must be adapted to YOUR model's output format.
// Common formats:
//   - YOLO: [batch, num_boxes, 5 + num_classes]  (x, y, w, h, obj_conf, class_scores...)
//   - SSD:  [boxes_tensor, scores_tensor, classes_tensor]
async function parseDetections(predictions, origWidth, origHeight) {
    const detections = [];

    // Example: generic output parsing (adapt to your model)
    // This is a placeholder that handles common output shapes
    let outputTensor;
    if (Array.isArray(predictions)) {
        outputTensor = predictions[0];
    } else {
        outputTensor = predictions;
    }

    const data = await outputTensor.data();
    const shape = outputTensor.shape;

    // Placeholder parsing logic - YOU MUST customize this
    // based on your specific model's output format
    const numDetections = shape[1] || 0;
    const stride = shape[2] || 6; // typically: x, y, w, h, confidence, class_id

    for (let i = 0; i < numDetections; i++) {
        const offset = i * stride;
        const x = data[offset];
        const y = data[offset + 1];
        const w = data[offset + 2];
        const h = data[offset + 3];
        const confidence = data[offset + 4];
        const classId = Math.round(data[offset + 5] || 0);

        if (confidence < NMS_SCORE_THRESHOLD) continue;

        detections.push({
            bbox: [
                (x - w / 2) * origWidth,
                (y - h / 2) * origHeight,
                w * origWidth,
                h * origHeight,
            ],
            score: confidence,
            label: LABELS[classId] || `Class ${classId}`,
            classId,
        });
    }

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

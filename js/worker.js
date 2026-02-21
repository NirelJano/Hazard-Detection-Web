// ============================================
// TensorFlow.js Web Worker - Hazard Detection
// ============================================
// This worker runs in a separate thread to keep
// the main UI thread smooth at 60 FPS.

importScripts('https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@4.17.0/dist/tf.min.js');

let model = null;
const MODEL_PATH = '/assets/model/model.json'; // Path to your custom model
const LABELS = ['Crack', 'Pothole', 'Bump', 'Debris']; // Swapped Crack and Pothole
const NMS_IOU_THRESHOLD = 0.5;
const NMS_SCORE_THRESHOLD = 0.45;

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
// YOLOv12 output format is typically: [batch_size, 4_bbox_coords + num_classes, num_anchors]
// For this model: [1, 6, 8400] -> (x_center, y_center, width, height, class0_conf, class1_conf)
async function parseDetections(predictions, origWidth, origHeight) {
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

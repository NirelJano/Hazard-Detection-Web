// ============================================
// Node.js Development Server
// ============================================

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 3000;

const MIME_TYPES = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'application/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.webp': 'image/webp',
    '.ico': 'image/x-icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
};

// Simple .env parser
function loadEnv() {
    const envPath = path.join(__dirname, '.env');
    const env = {};
    if (fs.existsSync(envPath)) {
        const content = fs.readFileSync(envPath, 'utf8');
        content.split('\n').forEach(line => {
            const match = line.match(/^\s*([\w.-]+)\s*=\s*(.*)?\s*$/);
            if (match) {
                const key = match[1];
                let value = match[2] || '';
                // Remove quotes
                if (value.startsWith('"') && value.endsWith('"')) value = value.slice(1, -1);
                if (value.startsWith("'") && value.endsWith("'")) value = value.slice(1, -1);
                env[key] = value.trim();
            }
        });
    }
    return env;
}

const server = http.createServer((req, res) => {
    // Remove query strings
    let filePath = req.url.split('?')[0];

    // Serve dynamic env config
    if (filePath === '/env.js') {
        const env = loadEnv();
        const config = {
            GOOGLE_MAPS_API_KEY: process.env.GOOGLE_MAPS_API_KEY || env.GOOGLE_MAPS_API_KEY || '',
            CLOUDINARY_CLOUD_NAME: process.env.CLOUDINARY_CLOUD_NAME || env.CLOUDINARY_CLOUD_NAME || '',
            CLOUDINARY_UPLOAD_PRESET: process.env.CLOUDINARY_UPLOAD_PRESET || env.CLOUDINARY_UPLOAD_PRESET || '',
        };
        res.writeHead(200, { 'Content-Type': 'application/javascript' });
        res.end(`window.ENV = ${JSON.stringify(config)};`);
        return;
    }

    // Serve dynamic Firebase config (keeps API keys out of git)
    if (filePath === '/firebase-config.js') {
        const env = loadEnv();
        const fb = {
            apiKey: process.env.FIREBASE_API_KEY || env.FIREBASE_API_KEY || '',
            authDomain: process.env.FIREBASE_AUTH_DOMAIN || env.FIREBASE_AUTH_DOMAIN || '',
            projectId: process.env.FIREBASE_PROJECT_ID || env.FIREBASE_PROJECT_ID || '',
            storageBucket: process.env.FIREBASE_STORAGE_BUCKET || env.FIREBASE_STORAGE_BUCKET || '',
            messagingSenderId: process.env.FIREBASE_MESSAGING_SENDER_ID || env.FIREBASE_MESSAGING_SENDER_ID || '',
            appId: process.env.FIREBASE_APP_ID || env.FIREBASE_APP_ID || '',
            measurementId: process.env.FIREBASE_MEASUREMENT_ID || env.FIREBASE_MEASUREMENT_ID || '',
        };
        const script = `
import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-app.js';
import { getAuth, onAuthStateChanged } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';
import { getFirestore } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { getAnalytics } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-analytics.js';

const firebaseConfig = ${JSON.stringify(fb, null, 4)};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const analytics = getAnalytics(app);

export { app, auth, db, analytics, onAuthStateChanged, firebaseConfig };
`;
        res.writeHead(200, { 'Content-Type': 'application/javascript' });
        res.end(script);
        return;
    }

    // Default to index.html
    if (filePath === '/') filePath = '/index.html';

    const fullPath = path.join(__dirname, filePath);
    const ext = path.extname(fullPath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    fs.readFile(fullPath, (err, data) => {
        if (err) {
            if (err.code === 'ENOENT') {
                // SPA fallback: serve index.html for missing routes
                fs.readFile(path.join(__dirname, 'index.html'), (err2, indexData) => {
                    if (err2) {
                        res.writeHead(500);
                        res.end('Server Error');
                        return;
                    }
                    res.writeHead(200, { 'Content-Type': 'text/html' });
                    res.end(indexData);
                });
            } else {
                res.writeHead(500);
                res.end('Server Error');
            }
            return;
        }

        // Disable caching globally to force updates
        res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
        res.setHeader('Pragma', 'no-cache');
        res.setHeader('Expires', '0');
        res.setHeader('Surrogate-Control', 'no-store');

        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
    });
});

server.listen(PORT, () => {
    console.log(`\n  🚀 Hazard Detection Web`);
    console.log(`  ➜ Local:   http://localhost:${PORT}`);
    console.log(`  ➜ Press Ctrl+C to stop\n`);
});

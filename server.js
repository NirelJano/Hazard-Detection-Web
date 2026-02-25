// ============================================
// Node.js Development Server
// ============================================

const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;

// Simple .env parser for local development fallback
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

// Serve dynamic environment variables to the frontend
app.get('/env.js', (req, res) => {
    const env = loadEnv();
    const config = {
        // Cloudinary config
        CLOUDINARY_CLOUD_NAME: process.env.CLOUDINARY_CLOUD_NAME || env.CLOUDINARY_CLOUD_NAME || '',
        CLOUDINARY_UPLOAD_PRESET: process.env.CLOUDINARY_UPLOAD_PRESET || env.CLOUDINARY_UPLOAD_PRESET || '',

        // Firebase config
        FIREBASE_API_KEY: process.env.FIREBASE_API_KEY || env.FIREBASE_API_KEY || '',
        FIREBASE_AUTH_DOMAIN: process.env.FIREBASE_AUTH_DOMAIN || env.FIREBASE_AUTH_DOMAIN || '',
        FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID || env.FIREBASE_PROJECT_ID || '',
        FIREBASE_STORAGE_BUCKET: process.env.FIREBASE_STORAGE_BUCKET || env.FIREBASE_STORAGE_BUCKET || '',
        FIREBASE_MESSAGING_SENDER_ID: process.env.FIREBASE_MESSAGING_SENDER_ID || env.FIREBASE_MESSAGING_SENDER_ID || '',
        FIREBASE_APP_ID: process.env.FIREBASE_APP_ID || env.FIREBASE_APP_ID || '',
        FIREBASE_MEASUREMENT_ID: process.env.FIREBASE_MEASUREMENT_ID || env.FIREBASE_MEASUREMENT_ID || '',

        // Mapbox config
        MAPBOX_ACCESS_TOKEN: process.env.MAPBOX_ACCESS_TOKEN || env.MAPBOX_ACCESS_TOKEN || '',
    };

    // Disable caching for env vars
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');

    res.type('application/javascript');
    res.send(`window.ENV = ${JSON.stringify(config)};`);
});

// Fix MIME type for .webmanifest (Express already handles .js correctly)
app.use((req, res, next) => {
    if (req.path.endsWith('.webmanifest')) {
        res.setHeader('Content-Type', 'application/manifest+json');
    }
    next();
});

// Serve static files from current directory
app.use(express.static(__dirname));

// Catch-all route for SPA navigation
// Static asset extensions (non-HTML) that are not found should return 404,
// NOT index.html – otherwise the browser gets HTML where it expects JS/CSS
// and throws: Uncaught SyntaxError: Unexpected token '<'
const STATIC_ASSET_RE = /\.(js|mjs|css|json|webmanifest|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf|eot|mp4|webm|map)$/i;

app.get(/^.*$/, (req, res) => {
    if (STATIC_ASSET_RE.test(req.path)) {
        // Return a clear 404 for missing static assets
        return res.status(404).type('text/plain').send(`404 – Not Found: ${req.path}`);
    }
    // HTML navigation – serve the SPA shell
    res.sendFile(path.join(__dirname, 'index.html'));
});

app.listen(PORT, () => {
    console.log(`\n  🚀 Hazard Detection Web`);
    console.log(`  ➜ Port:    ${PORT}`);
    console.log(`  ➜ Local:   http://localhost:${PORT}`);
    console.log(`  ➜ Env vars enabled dynamically\n`);
});

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
            GOOGLE_MAPS_API_KEY: env.GOOGLE_MAPS_API_KEY || '',
            CLOUDINARY_CLOUD_NAME: env.CLOUDINARY_CLOUD_NAME || '',
            CLOUDINARY_UPLOAD_PRESET: env.CLOUDINARY_UPLOAD_PRESET || '',
        };
        res.writeHead(200, { 'Content-Type': 'application/javascript' });
        res.end(`window.ENV = ${JSON.stringify(config)};`);
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

        res.writeHead(200, { 'Content-Type': contentType });
        res.end(data);
    });
});

server.listen(PORT, () => {
    console.log(`\n  🚀 Hazard Detection Web`);
    console.log(`  ➜ Local:   http://localhost:${PORT}`);
    console.log(`  ➜ Press Ctrl+C to stop\n`);
});

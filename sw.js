// ============================================
// Service Worker - Road Hazard Detection PWA
// ============================================

const CACHE_VERSION = '18'; // Lighthouse optimization: CLS, LCP, TBT, a11y, model caching
const CACHE_NAME = 'hazard-detect-v' + CACHE_VERSION;
const ASSETS_TO_CACHE = [
  '/',
  '/index.html',
  '/pages/login.html',
  '/pages/register.html',
  '/pages/dashboard.html',
  '/pages/upload.html',
  '/pages/live-detection.html',
  '/pages/settings.html',
  '/css/styles.css',
  '/css/dashboard.css',
  '/css/upload.css',
  '/css/live-detection.css',
  '/js/app.js',
  '/js/auth.js',
  '/js/dashboard.js',
  '/js/dashboard-map.js',
  '/js/dashboard-reports.js',
  '/js/dashboard-filters.js',
  '/js/upload.js',
  '/js/worker.js',
  '/js/live-detection.js',
  '/js/settings.js',
  '/js/geocode.js',
  '/manifest.json',
  '/robots.txt',
  '/assets/model/model.json',
  '/assets/model/group1-shard1of1.bin'
];


// Install: Cache core assets
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[SW] Caching core assets');
      return cache.addAll(ASSETS_TO_CACHE);
    })
  );
  self.skipWaiting();
});

// Activate: Clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key).catch(() => {
            // Cache may have already been deleted — ignore
          }))
      );
    })
  );
  self.clients.claim();
});

// Fetch: Cache-first, fallback to network
self.addEventListener('fetch', (event) => {
  // Skip non-GET requests
  if (event.request.method !== 'GET') return;

  // Skip Firebase, Google API, and Model requests (always network)
  const url = new URL(event.request.url);
  if (
    url.hostname.includes('googleapis.com') ||
    url.hostname.includes('firebaseio.com') ||
    url.hostname.includes('firestore.googleapis.com') ||
    url.hostname.includes('api.mapbox.com') ||
    url.pathname.startsWith('/__/auth') ||
    url.hostname.includes('firebaseapp.com') ||
    url.hostname.includes('identitytoolkit.googleapis.com')
  ) {
    return;
  }

  // Also skip anything that might be an auth callback (often has query params)
  if (url.searchParams.has('apiKey') || url.pathname.includes('handler')) {
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        return cachedResponse;
      }
      return fetch(event.request).then((networkResponse) => {
        // Cache successful responses for future use
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, responseClone);
          });
        }
        return networkResponse;
      });
    })
  );
});

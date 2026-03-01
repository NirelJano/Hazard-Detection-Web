// ============================================
// Dashboard Map Module
// ============================================

import { getDisplayImageUrl, openImageModal, scrollToReport } from './dashboard-reports.js';

let map = null;              // Mapbox GL map instance
let markers = [];            // Active marker references
let popups = [];             // Active popup references

// ---------- Dynamic Mapbox SDK Loader ----------
const MAPBOX_VERSION = '2.15.0';
let mapboxLoaded = false;
let mapboxLoadPromise = null;

function loadMapboxSDK() {
    if (mapboxLoaded) return Promise.resolve();
    if (mapboxLoadPromise) return mapboxLoadPromise;

    mapboxLoadPromise = new Promise((resolve, reject) => {
        // Load CSS
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = `https://api.mapbox.com/mapbox-gl-js/v${MAPBOX_VERSION}/mapbox-gl.css`;
        document.head.appendChild(link);

        // Load JS
        const script = document.createElement('script');
        script.src = `https://api.mapbox.com/mapbox-gl-js/v${MAPBOX_VERSION}/mapbox-gl.js`;
        script.onload = () => {
            mapboxLoaded = true;
            resolve();
        };
        script.onerror = () => reject(new Error('Failed to load Mapbox GL JS'));
        document.head.appendChild(script);
    });

    return mapboxLoadPromise;
}

export async function initMap(onReady) {
    try {
        await loadMapboxSDK();
    } catch (err) {
        console.error('[Dashboard] Failed to load Mapbox SDK:', err);
        if (onReady) onReady();
        return;
    }

    if (typeof mapboxgl === 'undefined') {
        console.error('[Dashboard] Mapbox GL JS was expected to be loaded but is not.');
        if (onReady) onReady();
        return;
    }

    try {
        mapboxgl.accessToken = window.ENV?.MAPBOX_ACCESS_TOKEN || '';

        map = new mapboxgl.Map({
            container: 'map',
            style: 'mapbox://styles/mapbox/streets-v12',
            center: [34.7818, 32.0853],   // Tel Aviv [lng, lat]
            zoom: 12
        });

        map.addControl(new mapboxgl.NavigationControl(), 'top-right');

        map.on('load', () => {
            if (onReady) onReady();
        });

    } catch (err) {
        console.error('[Dashboard] Mapbox initialization error:', err);
        if (onReady) onReady();
    }
}


// ---------- Map Markers ----------
export function updateMapMarkers(reports) {
    if (!map) return;

    // Clear existing markers
    markers.forEach(m => m.remove());
    popups.forEach(p => p.remove());
    markers = [];
    popups = [];

    const bounds = new mapboxgl.LngLatBounds();
    let hasValidCoords = false;

    reports.forEach((report) => {
        const coord = report.coordinate;
        if (!coord || coord.latitude == null || coord.longitude == null) return;

        const lng = coord.longitude;
        const lat = coord.latitude;
        hasValidCoords = true;
        bounds.extend([lng, lat]);

        // Build popup HTML
        const statusClass = `badge-${report.status?.replace(' ', '-') || 'new'}`;
        const dateStr = typeof report.date === 'string' ? report.date : '—';
        const popupHTML = `
            <div class="marker-popup">
                <div class="marker-popup-header">
                    <span class="marker-popup-type">${report.hazardType || 'Unknown'}</span>
                    <span class="badge ${statusClass} marker-popup-badge">${report.status || 'new'}</span>
                </div>
                <img
                    src="${getDisplayImageUrl(report.imageUrl)}"
                    alt="Hazard"
                    class="marker-popup-img"
                    data-full-src="${getDisplayImageUrl(report.imageUrl, { thumbnail: false })}"
                />
                <div class="marker-popup-details">
                    <p class="marker-popup-address">📍 ${report.address || 'No address'}</p>
                    <p class="marker-popup-date">${dateStr}</p>
                </div>
                <button class="marker-popup-goto" data-report-id="${report.id}">
                    📋 Go to report #${report.id || '-'}
                </button>
            </div>
        `;

        const popup = new mapboxgl.Popup({
            offset: 25,
            maxWidth: '280px',
            closeButton: true,
            closeOnClick: false
        }).setHTML(popupHTML);

        // After popup opens, attach event listeners
        popup.on('open', () => {
            setTimeout(() => {
                const popupEl = popup.getElement();
                if (!popupEl) return;

                const img = popupEl.querySelector('.marker-popup-img');
                if (img) {
                    img.addEventListener('click', () => {
                        openImageModal(img.dataset.fullSrc);
                    });
                }

                const gotoBtn = popupEl.querySelector('.marker-popup-goto');
                if (gotoBtn) {
                    gotoBtn.addEventListener('click', () => {
                        const reportId = gotoBtn.dataset.reportId;
                        scrollToReport(reportId);
                        popup.remove();
                    });
                }
            }, 50);
        });

        // Create custom marker element
        const el = document.createElement('div');
        el.className = 'hazard-marker';
        el.innerHTML = `
            <div class="hazard-marker-pin">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M12 2C8.13 2 5 5.13 5 9C5 14.25 12 22 12 22S19 14.25 19 9C19 5.13 15.87 2 12 2ZM12 11.5C10.62 11.5 9.5 10.38 9.5 9C9.5 7.62 10.62 6.5 12 6.5C13.38 6.5 14.5 7.62 14.5 9C14.5 10.38 13.38 11.5 12 11.5Z" fill="currentColor"/>
                </svg>
            </div>
        `;

        const marker = new mapboxgl.Marker(el)
            .setLngLat([lng, lat])
            .setPopup(popup)
            .addTo(map);

        markers.push(marker);
        popups.push(popup);
    });

    // Fit map bounds to show all markers
    if (hasValidCoords) {
        if (reports.filter(r => r.coordinate?.latitude != null).length === 1) {
            const single = reports.find(r => r.coordinate?.latitude != null);
            map.flyTo({
                center: [single.coordinate.longitude, single.coordinate.latitude],
                zoom: 14,
                duration: 1000
            });
        } else {
            map.fitBounds(bounds, {
                padding: { top: 50, bottom: 50, left: 50, right: 50 },
                maxZoom: 15,
                duration: 1000
            });
        }
    }
}

// Fly to a specific report's marker and open its popup
export function flyToReport(reportId, currentReports) {
    if (!map) return;

    const idx = currentReports.findIndex(r => String(r.id) === String(reportId));
    if (idx === -1) return;

    const report = currentReports[idx];
    const coord = report.coordinate;
    if (!coord || coord.latitude == null) return;

    popups.forEach(p => p.remove());

    map.flyTo({
        center: [coord.longitude, coord.latitude],
        zoom: 15,
        duration: 1200
    });

    setTimeout(() => {
        if (markers[idx]) {
            markers[idx].togglePopup();
        }
    }, 1300);

    const mapContainer = document.getElementById('map-container');
    if (mapContainer) {
        mapContainer.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
}

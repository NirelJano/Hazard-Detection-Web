// ============================================
// Dashboard Module (Map + Report Log)
// ============================================

import { auth, db } from '../firebase-config.js';
import { navigateTo, showToast } from './app.js';
import {
    collection,
    query,
    where,
    orderBy,
    onSnapshot
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { signOut } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';

let unsubscribe = null; // Firestore listener
let map = null;
let markers = [];

export function init() {
    setupLogout();
    loadReports();
    initMap();
}

// ---------- Logout ----------
function setupLogout() {
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', async () => {
            try {
                if (unsubscribe) unsubscribe();
                await signOut(auth);
                showToast('Signed out', 'info');
            } catch (err) {
                showToast('Failed to sign out', 'error');
            }
        });
    }
}

// ---------- Google Map ----------
function initMap() {
    const mapContainer = document.getElementById('map-container');
    if (!mapContainer || !window.google) {
        console.warn('[Dashboard] Google Maps not loaded yet');
        return;
    }

    map = new google.maps.Map(mapContainer, {
        center: { lat: 32.0853, lng: 34.7818 }, // Tel Aviv default
        zoom: 12,
        styles: getMapDarkStyle(),
        disableDefaultUI: true,
        zoomControl: true,
    });
}

// ---------- Firestore Real-time Listener ----------
function loadReports() {
    const user = auth.currentUser;
    if (!user) return;

    const reportsList = document.getElementById('reports-list');
    const reportsCount = document.getElementById('reports-count');

    const q = query(
        collection(db, 'reports'),
        where('reportedBy', '==', user.uid),
        orderBy('date', 'desc')
    );

    unsubscribe = onSnapshot(q, (snapshot) => {
        const reports = [];
        snapshot.forEach((doc) => reports.push({ id: doc.id, ...doc.data() }));

        // Update count
        if (reportsCount) reportsCount.textContent = reports.length;

        // Render list
        if (reportsList) {
            if (reports.length === 0) {
                reportsList.innerHTML = `
          <div class="text-center py-12 text-dark-400">
            <svg class="w-12 h-12 mx-auto mb-3 opacity-50" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
            </svg>
            <p>No reports yet</p>
            <p class="text-sm mt-1">Upload an image or use live detection to create your first report</p>
          </div>`;
            } else {
                reportsList.innerHTML = reports.map((r) => renderReportRow(r)).join('');
            }
        }

        // Update map markers
        updateMapMarkers(reports);
    }, (err) => {
        console.error('[Dashboard] Firestore listener error:', err);
    });
}

function renderReportRow(report) {
    const date = report.date?.toDate?.() ? report.date.toDate().toLocaleDateString() : '—';
    const statusClass = `badge-${report.status?.replace(' ', '-') || 'open'}`;

    return `
    <div class="glass-card-light p-4 flex items-center gap-4 animate-fade-in">
      <img
        src="${report.imageUrl || 'assets/icons/icon-192.png'}"
        alt="Hazard"
        class="w-14 h-14 rounded-lg object-cover flex-shrink-0"
        loading="lazy"
      />
      <div class="flex-1 min-w-0">
        <p class="font-semibold text-sm truncate">${report.hazardType || 'Unknown'}</p>
        <p class="text-dark-400 text-xs truncate">${report.address || 'No address'}</p>
        <p class="text-dark-500 text-xs mt-0.5">${date}</p>
      </div>
      <span class="badge ${statusClass}">${report.status || 'open'}</span>
    </div>`;
}

// ---------- Map Markers ----------
function updateMapMarkers(reports) {
    if (!map) return;

    // Clear old markers
    markers.forEach((m) => m.setMap(null));
    markers = [];

    reports.forEach((r) => {
        if (!r.coordinate) return;
        const lat = r.coordinate.lat || r.coordinate.latitude;
        const lng = r.coordinate.lng || r.coordinate.longitude;
        if (!lat || !lng) return;

        const marker = new google.maps.Marker({
            position: { lat, lng },
            map,
            title: r.hazardType || 'Hazard',
            icon: {
                path: google.maps.SymbolPath.CIRCLE,
                scale: 8,
                fillColor: getStatusColor(r.status),
                fillOpacity: 0.9,
                strokeColor: '#fff',
                strokeWeight: 2,
            },
        });

        const infoWindow = new google.maps.InfoWindow({
            content: `
        <div style="color:#1e293b;font-family:Inter,sans-serif;max-width:200px">
          <strong>${r.hazardType}</strong><br/>
          <span style="font-size:12px;color:#64748b">${r.address || ''}</span>
        </div>`,
        });

        marker.addListener('click', () => infoWindow.open(map, marker));
        markers.push(marker);
    });

    // Fit bounds if there are markers
    if (markers.length > 0) {
        const bounds = new google.maps.LatLngBounds();
        markers.forEach((m) => bounds.extend(m.getPosition()));
        map.fitBounds(bounds, 60);
    }
}

function getStatusColor(status) {
    switch (status) {
        case 'fixed': return '#22c55e';
        case 'in-progress': return '#f59e0b';
        default: return '#ef4444';
    }
}

// ---------- Dark Map Style ----------
function getMapDarkStyle() {
    return [
        { elementType: 'geometry', stylers: [{ color: '#1e293b' }] },
        { elementType: 'labels.text.stroke', stylers: [{ color: '#0f172a' }] },
        { elementType: 'labels.text.fill', stylers: [{ color: '#94a3b8' }] },
        { featureType: 'road', elementType: 'geometry', stylers: [{ color: '#334155' }] },
        { featureType: 'road', elementType: 'labels.text.fill', stylers: [{ color: '#64748b' }] },
        { featureType: 'water', elementType: 'geometry', stylers: [{ color: '#0f172a' }] },
        { featureType: 'poi', elementType: 'labels', stylers: [{ visibility: 'off' }] },
    ];
}

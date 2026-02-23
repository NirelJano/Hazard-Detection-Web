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

export function init() {
    setupLogout();
    setupImageModal();
    loadReports();

    if (window.isGovmapLoaded) {
        initMap();
    } else {
        document.addEventListener('govmap_ready', initMap, { once: true });
    }
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



// ---------- Govmap (מפ"י) Map ----------
function initMap() {
    const gmap = window.govmap;

    if (typeof gmap === 'undefined') {
        console.error('[Dashboard] Govmap SDK was expected to be loaded but is not.');
        return;
    }

    try {
        gmap.createMap('map', {
            token: '9a416d69-ade2-4809-906d-006325501865',
            center: { x: 180000, y: 660000 },
            zoomLevel: 10,
            layers: ['STREET_LABELS']
        });
        console.log('[Dashboard] Govmap map initialized');
    } catch (err) {
        console.error('[Dashboard] Govmap initialization error:', err);
    }
}

// ---------- Firestore Real-time Listener ----------
function loadReports() {
    const user = auth.currentUser;
    if (!user) return;

    const reportsList = document.getElementById('reports-list');
    const reportsCount = document.getElementById('reports-count');

    const username = user.displayName || user.email || 'Unknown User';

    const q = query(
        collection(db, 'reports'),
        where('reportedBy', '==', username)
    );

    unsubscribe = onSnapshot(q, (snapshot) => {
        const reports = [];
        snapshot.forEach((doc) => reports.push({ docId: doc.id, ...doc.data() }));

        // Sort by id descending: newest (highest id) at the top of the list
        reports.sort((a, b) => (b.id || 0) - (a.id || 0));

        const reportsCount = document.getElementById('reports-count');
        const newCount = document.getElementById('new-count');
        const inProgressCount = document.getElementById('pending-count');
        const fixedCount = document.getElementById('fixed-count');

        // Update count
        if (reportsCount) reportsCount.textContent = reports.length;
        if (newCount) newCount.textContent = reports.filter(r => r.status === 'new').length;
        if (inProgressCount) inProgressCount.textContent = reports.filter(r => r.status === 'in-progress').length;
        if (fixedCount) fixedCount.textContent = reports.filter(r => r.status === 'fixed').length;

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
                reportsList.innerHTML = `
                <div class="w-full overflow-x-auto">
                    <table class="w-full text-left border-collapse min-w-[700px]">
                        <thead>
                            <tr class="border-b border-white/10 text-dark-400 text-xs uppercase tracking-wider">
                                <th class="py-3 px-4 font-medium">ID</th>
                                <th class="py-3 px-4 font-medium">Hazard Type</th>
                                <th class="py-3 px-4 font-medium">Location</th>
                                <th class="py-3 px-4 font-medium">Date</th>
                                <th class="py-3 px-4 font-medium text-center">Image</th>
                                <th class="py-3 px-4 font-medium">Status</th>
                                <th class="py-3 px-4 font-medium">Reported By</th>
                            </tr>
                        </thead>
                        <tbody class="divide-y divide-white/5">
                            ${reports.map((r) => renderReportRow(r)).join('')}
                        </tbody>
                    </table>
                </div>`;

                // Add click listeners for images
                document.querySelectorAll('.report-img-clickable').forEach(img => {
                    img.addEventListener('click', (e) => {
                        openImageModal(e.target.src);
                    });
                });
            }
        }

    }, (err) => {
        console.error('[Dashboard] Firestore listener error:', err);
    });
}

function renderReportRow(report) {
    const dateStr = typeof report.date === 'string' ? report.date : (report.date?.toDate?.() ? report.date.toDate().toLocaleDateString() : '—');
    const statusClass = `badge-${report.status?.replace(' ', '-') || 'new'}`;

    return `
    <tr class="hover:bg-white/5 transition-colors group">
      <td class="py-3 px-4 text-sm whitespace-nowrap">#${report.id || '-'}</td>
      <td class="py-3 px-4 text-sm whitespace-nowrap">${report.hazardType || 'Unknown'}</td>
      <td class="py-3 px-4 text-sm max-w-[200px] truncate" title="${report.address || ''}">${report.address || 'No address'}</td>
      <td class="py-3 px-4 text-sm whitespace-nowrap text-dark-400">${dateStr}</td>
      <td class="py-3 px-4 flex justify-center">
        <img
          src="${report.imageUrl || 'assets/icons/icon-192.png'}"
          alt="Hazard"
          class="w-12 h-12 rounded-lg object-cover flex-shrink-0 cursor-pointer report-img-clickable hover:opacity-80 transition-opacity"
          loading="lazy"
        />
      </td>
      <td class="py-3 px-4">
        <span class="badge ${statusClass}">${report.status || 'new'}</span>
      </td>
      <td class="py-3 px-4 text-sm font-medium whitespace-nowrap">${report.reportedBy || 'Unknown'}</td>
    </tr>`;
}

// ---------- Image Modal ----------
function openImageModal(src) {
    const modal = document.getElementById('image-modal');
    const modalImg = document.getElementById('modal-image');
    if (modal && modalImg) {
        modalImg.src = src;
        modal.classList.remove('hidden');
        // Small delay for transition
        setTimeout(() => {
            modal.classList.remove('opacity-0');
        }, 10);
    }
}

function setupImageModal() {
    const modal = document.getElementById('image-modal');
    const closeBtn = document.getElementById('close-modal-btn');

    if (modal && closeBtn) {
        const closeModal = () => {
            modal.classList.add('opacity-0');
            setTimeout(() => {
                modal.classList.add('hidden');
                document.getElementById('modal-image').src = '';
            }, 300);
        };

        closeBtn.addEventListener('click', closeModal);
        modal.addEventListener('click', (e) => {
            if (e.target === modal) closeModal();
        });
    }
}



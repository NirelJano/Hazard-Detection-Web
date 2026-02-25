// ============================================
// Dashboard Module (Main Orchestrator)
// ============================================

import { auth, db } from '../firebase-config.js';
import { navigateTo, showToast } from './app.js';
import {
    collection,
    query,
    where,
    onSnapshot
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { signOut } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';

import { initMap } from './dashboard-map.js';
import { setupFilters, populateFilterOptions } from './dashboard-filters.js';
import {
    setupPagination,
    setupImageModal,
    setAllReports,
    renderFilteredReports
} from './dashboard-reports.js';

let unsubscribe = null;      // Firestore listener

export function init() {
    setupLogout();
    setupImageModal();
    setupFilters(() => renderFilteredReports());
    setupPagination();

    initMap(() => {
        loadReports();
    });
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

// ---------- Firestore Real-time Listener ----------
function loadReports() {
    const user = auth.currentUser;
    if (!user) return;

    const username = user.displayName || user.email || 'Unknown User';

    const q = query(
        collection(db, 'reports'),
        where('reportedBy', '==', username)
    );

    unsubscribe = onSnapshot(q, (snapshot) => {
        const reports = [];
        snapshot.forEach((doc) => reports.push({ docId: doc.id, ...doc.data() }));

        // Sort by id descending
        reports.sort((a, b) => (b.id || 0) - (a.id || 0));

        // Store all reports (unfiltered)
        setAllReports(reports);

        // Populate dynamic filter options
        populateFilterOptions(reports);

        // Render with current filters applied (also updates map markers)
        renderFilteredReports();

    }, (err) => {
        console.error('[Dashboard] Firestore listener error:', err);
    });
}

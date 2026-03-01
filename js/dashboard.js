import { auth, db } from '../firebase-config.js';
import { navigateTo, showToast } from './app.js';
import {
    collection,
    query,
    where,
    doc,
    getDoc,
    getDocs
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { signOut } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';

import { initMap } from './dashboard-map.js';
import { setupFilters, populateFilterOptions } from './dashboard-filters.js';
import {
    setupPagination,
    setupImageModal,
    setAllReports,
    renderFilteredReports,
    setupAdminToolbar,
    toggleShowAllMarkers
} from './dashboard-reports.js';

export let isAdmin = false;  // Populated after auth check

export async function init() {
    setupLogout();
    setupImageModal();
    setupFilters(() => renderFilteredReports());
    setupPagination();

    // Detect admin role before loading map / reports
    await detectAdminRole();

    initMap(() => {
        loadReports();
    });

    // Wire up admin "Show All Markers" button
    const showAllBtn = document.getElementById('show-all-markers-btn');
    if (showAllBtn) {
        showAllBtn.addEventListener('click', toggleShowAllMarkers);
    }
}

// ---------- Logout ----------
function setupLogout() {
    const logoutBtn = document.getElementById('logout-btn');
    if (logoutBtn) {
        logoutBtn.addEventListener('click', async () => {
            try {
                await signOut(auth);
                showToast('Signed out', 'info');
            } catch (err) {
                showToast('Failed to sign out', 'error');
            }
        });
    }
}

// ---------- Admin Role Detection ----------
async function detectAdminRole() {
    isAdmin = false; // Reset role on every auth check to prevent SPA state leaks
    const user = auth.currentUser;
    if (!user) return;
    try {
        const userDoc = await getDoc(doc(db, 'users', user.uid));
        if (userDoc.exists() && userDoc.data().type === 'admin') {
            isAdmin = true;
        }
    } catch (err) {
        console.warn('[Dashboard] Could not read user role:', err);
    }
    // Wire up the admin toolbar based on role
    setupAdminToolbar(isAdmin);
}

// ---------- Firestore Loader ----------
async function loadReports() {
    const user = auth.currentUser;
    if (!user) return;

    const username = user.displayName || user.email || 'Unknown User';

    try {
        // Build query: admins see ALL reports; regular users only their own
        const q = isAdmin
            ? query(collection(db, 'reports'))
            : query(collection(db, 'reports'), where('reportedBy', '==', username));

        const snapshot = await getDocs(q);

        const reports = [];
        snapshot.forEach((docSnap) => reports.push({ docId: docSnap.id, ...docSnap.data() }));

        // Sort by id descending (newest first)
        reports.sort((a, b) => (b.id || 0) - (a.id || 0));

        // Store all reports (unfiltered)
        setAllReports(reports);

        // Populate dynamic filter options
        populateFilterOptions(reports);

        // Render with current filters applied (also updates map markers)
        // Per-page display (25/50/100) is handled by dashboard-reports.js pagination
        renderFilteredReports();

    } catch (err) {
        console.error('[Dashboard] Firestore query error:', err);
        showToast('Failed to load reports', 'error');
    }
}

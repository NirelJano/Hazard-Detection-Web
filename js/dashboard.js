// ============================================
// Dashboard Module (Main Orchestrator)
// ============================================

import { auth, db } from '../firebase-config.js';
import { navigateTo, showToast } from './app.js';
import {
    collection,
    query,
    where,
    onSnapshot,
    doc,
    getDoc
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { signOut } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';

import { initMap } from './dashboard-map.js';
import { setupFilters, populateFilterOptions } from './dashboard-filters.js';
import {
    setupPagination,
    setupImageModal,
    setAllReports,
    renderFilteredReports,
    setupAdminToolbar
} from './dashboard-reports.js';

let unsubscribe = null;      // Firestore listener
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

// ---------- Admin Role Detection ----------
async function detectAdminRole() {
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

// ---------- Firestore Real-time Listener ----------
function loadReports() {
    const user = auth.currentUser;
    if (!user) return;

    const username = user.displayName || user.email || 'Unknown User';

    // Admins see ALL reports; regular users only see their own
    const q = isAdmin
        ? query(collection(db, 'reports'))
        : query(collection(db, 'reports'), where('reportedBy', '==', username));

    unsubscribe = onSnapshot(q, (snapshot) => {
        const reports = [];
        snapshot.forEach((docSnap) => reports.push({ docId: docSnap.id, ...docSnap.data() }));

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

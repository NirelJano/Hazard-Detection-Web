import { auth, db } from '../firebase-config.js';
import { navigateTo, showToast } from './app.js';
import {
    collection,
    query,
    where,
    doc,
    getDoc,
    onSnapshot
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';

import { signOut } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';

import { initMap } from './dashboard-map.js';
import { setupFilters, populateFilterOptions } from './dashboard-filters.js';
import {
    setupPagination,
    setupSorting,
    setupImageModal,
    setAllReports,
    renderFilteredReports,
    setupAdminToolbar,
    toggleShowAllMarkers
} from './dashboard-reports.js';

export let isAdmin = false;  // Populated after auth check
let unsubscribeReports = null; // Store realtime listener


export async function init() {
    setupLogout();
    setupImageModal();
    setupFilters(() => renderFilteredReports());
    setupPagination();
    setupSorting();

    // Detect admin role before loading map / reports
    await detectAdminRole();

    // Defer map loading to reduce TBT — let the DOM finish rendering first
    const deferredMapInit = () => {
        initMap(() => {
            loadReports();
        });
    };

    if ('requestIdleCallback' in window) {
        requestIdleCallback(deferredMapInit, { timeout: 2000 });
    } else {
        setTimeout(deferredMapInit, 100);
    }

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
        // Build query: all authenticated users can see ALL reports
        const q = query(collection(db, 'reports'));

        // Clear existing listener if loadReports is called again
        if (unsubscribeReports) {
            unsubscribeReports();
        }

        // Use onSnapshot for real-time updates (creations, deletions, edits)
        unsubscribeReports = onSnapshot(q, (snapshot) => {
            const reports = [];
            snapshot.forEach((docSnap) => reports.push({ docId: docSnap.id, ...docSnap.data() }));

            // Log change context for debugging
            const changes = snapshot.docChanges();
            if (changes.length > 0) {
                console.log(`[Dashboard] Snapshot sync: ${changes.length} change(s). Total reports: ${reports.length}`);
                changes.forEach(change => {
                    console.log(`[Dashboard] Change type: ${change.type}, ID: ${change.doc.id}`);
                });
            }

            // Sort by id descending (newest first)
            reports.sort((a, b) => (b.id || 0) - (a.id || 0));

            // Store all reports (unfiltered)
            setAllReports(reports);

            // Populate dynamic filter options
            populateFilterOptions(reports);

            // Render with current filters applied. 
            // Pass 'false' to preserve the user's current pagination page during live updates.
            renderFilteredReports(false);
        }, (err) => {
            console.error('[Dashboard] Real-time listener error:', err);
            showToast('Lost connection to live reports', 'error');
        });

    } catch (err) {
        console.error('[Dashboard] Failed to set up real-time listener:', err);
        showToast('Failed to load reports', 'error');
    }

}

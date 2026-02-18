// ============================================
// App Router & SPA Navigation
// ============================================

import { auth, onAuthStateChanged } from '../firebase-config.js';

// ---------- Router ----------
const routes = {
    login: 'pages/login.html',
    register: 'pages/register.html',
    dashboard: 'pages/dashboard.html',
    upload: 'pages/upload.html',
    'live-detection': 'pages/live-detection.html',
    settings: 'pages/settings.html',
};

const appContainer = document.getElementById('app');

/**
 * Navigate to a given route name.
 * @param {string} route - one of the keys in `routes`
 */
export async function navigateTo(route) {
    const path = routes[route];
    if (!path) {
        console.error(`[Router] Unknown route: ${route}`);
        return;
    }

    try {
        const res = await fetch(path);
        if (!res.ok) throw new Error(`Failed to load ${path}`);
        const html = await res.text();
        appContainer.innerHTML = html;

        // Dynamically load the matching JS module
        const moduleMap = {
            login: '../js/auth.js',
            register: '../js/auth.js',
            dashboard: '../js/dashboard.js',
            upload: '../js/upload.js',
            'live-detection': '../js/live-detection.js',
            settings: '../js/settings.js',
        };

        if (moduleMap[route]) {
            const mod = await import(moduleMap[route]);
            if (mod.init) mod.init(route);
        }

        // Update active nav if visible
        updateActiveNav(route);

        // Push to browser history
        window.history.pushState({ route }, '', `#${route}`);

    } catch (err) {
        console.error('[Router]', err);
        appContainer.innerHTML = `
      <div class="flex flex-col items-center justify-center min-h-screen gap-4 p-6 text-center">
        <p class="text-dark-400 text-lg">Failed to load page</p>
        <button onclick="window.location.reload()" class="btn btn-primary">Reload</button>
      </div>`;
    }
}

/**
 * Highlight the active bottom nav item.
 */
function updateActiveNav(route) {
    document.querySelectorAll('.nav-item').forEach((el) => {
        el.classList.toggle('active', el.dataset.route === route);
    });
}

// ---------- Browser Back/Forward ----------
window.addEventListener('popstate', (e) => {
    if (e.state && e.state.route) {
        navigateTo(e.state.route);
    }
});

// ---------- Auth State Observer ----------
onAuthStateChanged(auth, (user) => {
    const hash = window.location.hash.replace('#', '');

    if (user) {
        // User is signed in – go to requested page or dashboard
        const protectedRoutes = ['dashboard', 'upload', 'live-detection', 'settings'];
        if (protectedRoutes.includes(hash)) {
            navigateTo(hash);
        } else {
            navigateTo('dashboard');
        }
    } else {
        // Not signed in – show login (allow register too)
        if (hash === 'register') {
            navigateTo('register');
        } else {
            navigateTo('login');
        }
    }
});

// ---------- Global Helpers ----------

/**
 * Show a toast notification.
 * @param {string} message
 * @param {'success'|'error'|'info'} type
 */
export function showToast(message, type = 'info') {
    // Remove existing
    document.querySelectorAll('.toast').forEach((t) => t.remove());

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    document.body.appendChild(toast);

    requestAnimationFrame(() => {
        toast.classList.add('show');
    });

    setTimeout(() => {
        toast.classList.remove('show');
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// Expose globally for inline handlers
window.navigateTo = navigateTo;
window.showToast = showToast;

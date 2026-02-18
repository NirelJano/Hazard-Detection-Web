// ============================================
// Settings & Permissions Module
// ============================================

import { auth } from '../firebase-config.js';
import { showToast } from './app.js';
import {
    updatePassword,
    reauthenticateWithCredential,
    EmailAuthProvider
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';

export function init() {
    checkPermissions();
    setupChangePassword();
}

// ---------- Permission Status ----------
async function checkPermissions() {
    // Camera
    const cameraStatus = document.getElementById('camera-permission');
    try {
        const cam = await navigator.permissions.query({ name: 'camera' });
        updatePermissionUI(cameraStatus, cam.state);
        cam.onchange = () => updatePermissionUI(cameraStatus, cam.state);
    } catch {
        if (cameraStatus) cameraStatus.textContent = 'Unknown';
    }

    // Location
    const locationStatus = document.getElementById('location-permission');
    try {
        const loc = await navigator.permissions.query({ name: 'geolocation' });
        updatePermissionUI(locationStatus, loc.state);
        loc.onchange = () => updatePermissionUI(locationStatus, loc.state);
    } catch {
        if (locationStatus) locationStatus.textContent = 'Unknown';
    }
}

function updatePermissionUI(el, state) {
    if (!el) return;
    const labels = {
        granted: '✅ Granted',
        denied: '❌ Denied',
        prompt: '⏳ Not requested',
    };
    el.textContent = labels[state] || state;
    el.className = `text-sm font-medium ${state === 'granted' ? 'text-success' :
            state === 'denied' ? 'text-danger' :
                'text-warning'
        }`;
}

// ---------- Change Password ----------
function setupChangePassword() {
    const form = document.getElementById('change-password-form');
    if (!form) return;

    form.addEventListener('submit', async (e) => {
        e.preventDefault();
        const oldPw = form.querySelector('#old-password').value;
        const newPw = form.querySelector('#new-password').value;
        const confPw = form.querySelector('#confirm-password').value;

        if (!oldPw || !newPw || !confPw) {
            showToast('Please fill in all fields', 'error');
            return;
        }

        if (newPw !== confPw) {
            showToast('New passwords do not match', 'error');
            return;
        }

        // Validate new password
        if (newPw.length < 8 || !/[A-Z]/.test(newPw) || !/[a-z]/.test(newPw)) {
            showToast('Password must be 8+ chars with uppercase & lowercase', 'error');
            return;
        }

        const user = auth.currentUser;
        if (!user || !user.email) {
            showToast('Cannot change password for Google-only accounts', 'error');
            return;
        }

        try {
            // Re-authenticate
            const credential = EmailAuthProvider.credential(user.email, oldPw);
            await reauthenticateWithCredential(user, credential);

            // Update password
            await updatePassword(user, newPw);
            showToast('Password updated!', 'success');
            form.reset();
        } catch (err) {
            console.error('[Settings] Password change error:', err);
            if (err.code === 'auth/wrong-password') {
                showToast('Current password is incorrect', 'error');
            } else {
                showToast('Failed to update password', 'error');
            }
        }
    });
}

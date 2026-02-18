// ============================================
// Authentication Module (Firebase Auth)
// ============================================

import { auth, db } from '../firebase-config.js';
import {
    createUserWithEmailAndPassword,
    signInWithEmailAndPassword,
    GoogleAuthProvider,
    signInWithPopup,
    updateProfile
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';
import {
    doc,
    setDoc,
    serverTimestamp
} from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { navigateTo, showToast } from './app.js';

// ---------- Password Validation Rules ----------
const PASSWORD_RULES = {
    minLength: 8,
    hasUppercase: /[A-Z]/,
    hasLowercase: /[a-z]/,
};

function validatePassword(password) {
    const errors = [];
    if (password.length < PASSWORD_RULES.minLength) {
        errors.push(`Minimum ${PASSWORD_RULES.minLength} characters`);
    }
    if (!PASSWORD_RULES.hasUppercase.test(password)) {
        errors.push('At least 1 uppercase letter');
    }
    if (!PASSWORD_RULES.hasLowercase.test(password)) {
        errors.push('At least 1 lowercase letter');
    }
    return errors;
}

// ---------- Init ----------
export function init(route) {
    if (route === 'login') {
        setupLogin();
    } else if (route === 'register') {
        setupRegister();
    }
}

// ---------- Login ----------
function setupLogin() {
    const form = document.getElementById('login-form');
    const googleBtn = document.getElementById('google-login-btn');

    if (form) {
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const email = form.querySelector('#login-email').value.trim();
            const password = form.querySelector('#login-password').value;

            if (!email || !password) {
                showToast('Please fill in all fields', 'error');
                return;
            }

            setLoading(form, true);
            try {
                await signInWithEmailAndPassword(auth, email, password);
                showToast('Welcome back!', 'success');
            } catch (err) {
                console.error('[Auth] Login error:', err);
                showToast(friendlyError(err.code), 'error');
            } finally {
                setLoading(form, false);
            }
        });
    }

    if (googleBtn) {
        googleBtn.addEventListener('click', handleGoogleSignIn);
    }
}

// ---------- Register ----------
function setupRegister() {
    const form = document.getElementById('register-form');
    const googleBtn = document.getElementById('google-register-btn');

    if (form) {
        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const username = form.querySelector('#register-username').value.trim();
            const email = form.querySelector('#register-email').value.trim();
            const password = form.querySelector('#register-password').value;
            const confirm = form.querySelector('#register-confirm').value;

            // Validation
            if (!username || !email || !password || !confirm) {
                showToast('Please fill in all fields', 'error');
                return;
            }

            if (password !== confirm) {
                showToast('Passwords do not match', 'error');
                return;
            }

            const pwErrors = validatePassword(password);
            if (pwErrors.length > 0) {
                showToast(pwErrors.join(', '), 'error');
                return;
            }

            setLoading(form, true);
            try {
                const cred = await createUserWithEmailAndPassword(auth, email, password);
                await updateProfile(cred.user, { displayName: username });

                // Save user doc in Firestore
                await setDoc(doc(db, 'users', cred.user.uid), {
                    username,
                    email,
                    createdAt: serverTimestamp(),
                    type: 'user',
                });

                showToast('Account created!', 'success');
            } catch (err) {
                console.error('[Auth] Register error:', err);
                showToast(friendlyError(err.code), 'error');
            } finally {
                setLoading(form, false);
            }
        });
    }

    if (googleBtn) {
        googleBtn.addEventListener('click', handleGoogleSignIn);
    }
}

// ---------- Google Sign-In ----------
async function handleGoogleSignIn() {
    try {
        const provider = new GoogleAuthProvider();
        const result = await signInWithPopup(auth, provider);

        // Create user doc if first time
        await setDoc(doc(db, 'users', result.user.uid), {
            username: result.user.displayName || 'Google User',
            email: result.user.email,
            createdAt: serverTimestamp(),
            type: 'user',
        }, { merge: true });

        showToast('Signed in with Google!', 'success');
    } catch (err) {
        console.error('[Auth] Google sign-in error:', err);
        if (err.code !== 'auth/popup-closed-by-user') {
            showToast('Google sign-in failed', 'error');
        }
    }
}

// ---------- Helpers ----------
function setLoading(form, loading) {
    const btn = form.querySelector('button[type="submit"]');
    if (btn) {
        btn.disabled = loading;
        btn.innerHTML = loading
            ? '<div class="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin"></div>'
            : btn.dataset.label || 'Submit';
    }
}

function friendlyError(code) {
    const map = {
        'auth/email-already-in-use': 'Email already in use',
        'auth/invalid-email': 'Invalid email address',
        'auth/user-not-found': 'No account found',
        'auth/wrong-password': 'Incorrect password',
        'auth/too-many-requests': 'Too many attempts. Please wait.',
        'auth/weak-password': 'Password is too weak',
        'auth/invalid-credential': 'Invalid email or password',
    };
    return map[code] || 'An error occurred. Please try again.';
}

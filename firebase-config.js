// ============================================
// Firebase Configuration & Initialization
// ============================================

import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-app.js';
import { getAuth, onAuthStateChanged } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';
import { getFirestore } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { getAnalytics } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-analytics.js';

const firebaseConfig = {
    apiKey: window.ENV?.FIREBASE_API_KEY || "",
    authDomain: window.ENV?.FIREBASE_AUTH_DOMAIN || "",
    projectId: window.ENV?.FIREBASE_PROJECT_ID || "",
    storageBucket: window.ENV?.FIREBASE_STORAGE_BUCKET || "",
    messagingSenderId: window.ENV?.FIREBASE_MESSAGING_SENDER_ID || "",
    appId: window.ENV?.FIREBASE_APP_ID || "",
    measurementId: window.ENV?.FIREBASE_MEASUREMENT_ID || ""
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const analytics = getAnalytics(app);

export { app, auth, db, analytics, onAuthStateChanged, firebaseConfig };

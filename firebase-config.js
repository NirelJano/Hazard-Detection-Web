// ============================================
// Firebase Configuration & Initialization
// ============================================

import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-app.js';
import { getAuth, onAuthStateChanged } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-auth.js';
import { getFirestore } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-firestore.js';
import { getAnalytics } from 'https://www.gstatic.com/firebasejs/12.9.0/firebase-analytics.js';

const firebaseConfig = {
    apiKey: "AIzaSyA7y-BR5x82V0Lh9sTxFzNWk1Q9of77yZU",
    authDomain: "hazard-detection-web.firebaseapp.com",
    projectId: "hazard-detection-web",
    storageBucket: "hazard-detection-web.firebasestorage.app",
    messagingSenderId: "798443612965",
    appId: "1:798443612965:web:d8792b8fb4c49bd5ac88cc",
    measurementId: "G-TRJHD6BK9M"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const analytics = getAnalytics(app);

export { app, auth, db, analytics, onAuthStateChanged };

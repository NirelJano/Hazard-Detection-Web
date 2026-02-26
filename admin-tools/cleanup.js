require('dotenv').config({ path: '../.env' }); // Load the project's root .env file
const cloudinary = require('cloudinary').v2;
const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

// 1. Initialize Firebase Admin
// You MUST place your serviceAccountKey.json file in this directory
const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(serviceAccountPath)) {
    console.error('❌ ERROR: Missing serviceAccountKey.json');
    console.error('   Please generate a Firebase Admin private key from the Firebase Console,');
    console.error('   save it inside the "admin-tools" folder as "serviceAccountKey.json", and run again.');
    process.exit(1);
}

const serviceAccount = require(serviceAccountPath);

if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}
const db = admin.firestore();

// 2. Initialize Cloudinary
if (!process.env.CLOUDINARY_CLOUD_NAME || !process.env.CLOUDINARY_API_KEY || !process.env.CLOUDINARY_API_SECRET) {
    console.error('❌ ERROR: Missing Cloudinary credentials in the .env file.');
    process.exit(1);
}

cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET
});

// Helper function to extract Cloudinary public_id from a URL
function getPublicIdFromUrl(url) {
    if (!url || !url.includes("cloudinary.com")) return null;
    const urlParts = url.split('/');
    const versionIndex = urlParts.findIndex(part => part.match(/^v\d+$/));

    let pathAfterVersion = [];
    if (versionIndex !== -1) {
        pathAfterVersion = urlParts.slice(versionIndex + 1);
    } else {
        const uploadIndex = urlParts.findIndex(part => part === 'upload');
        if (uploadIndex !== -1) {
            pathAfterVersion = urlParts.slice(uploadIndex + 1);
        } else {
            return null;
        }
    }
    const fullPathWithExtension = pathAfterVersion.join('/');
    return fullPathWithExtension.replace(/\.[^/.]+$/, ""); // Strip file extension
}

async function runCleanup() {
    console.log('🧹 Starting Cloudinary Orphaned Image Cleanup...');

    try {
        // Step A: Fetch all active reports from Firestore
        console.log('Fetching active reports from Firestore...');
        const snapshot = await db.collection('reports').get();
        const activePublicIds = new Set();

        snapshot.forEach(doc => {
            const data = doc.data();
            const publicId = getPublicIdFromUrl(data.imageUrl);
            if (publicId) activePublicIds.add(publicId);
        });
        console.log(`✅ Found ${activePublicIds.size} active images in Firestore.`);

        // Step B: Fetch ALL resources from Cloudinary
        console.log('Fetching all images from Cloudinary (this might take a moment)...');
        let cloudinaryResources = [];
        let nextCursor = null;

        do {
            const result = await cloudinary.api.resources({
                type: 'upload',
                max_results: 500, // Fetch up to 500 at a time
                next_cursor: nextCursor
            });

            cloudinaryResources = cloudinaryResources.concat(result.resources);
            nextCursor = result.next_cursor;
        } while (nextCursor);

        console.log(`✅ Found ${cloudinaryResources.length} total images in Cloudinary.`);

        // Step C: Identify orphaned images
        const orphanedPublicIds = [];
        cloudinaryResources.forEach(resource => {
            if (!activePublicIds.has(resource.public_id)) {
                orphanedPublicIds.push(resource.public_id);
            }
        });

        console.log(`🔍 Found ${orphanedPublicIds.length} orphaned images that are no longer in Firestore.`);

        // Step D: Delete them
        if (orphanedPublicIds.length === 0) {
            console.log('✨ All clean! No orphaned images to delete.');
            process.exit(0);
        }

        console.log('🗑️  Deleting orphaned images...');
        let deletedCount = 0;
        let errorCount = 0;

        // Delete individually to avoid Cloudinary rate limits on bulk deletes if the list is huge,
        // or we could use the bulk delete API. We'll use bulk delete for efficiency:
        // Cloudinary bulk delete allows up to 100 public_ids per request.
        for (let i = 0; i < orphanedPublicIds.length; i += 100) {
            const batch = orphanedPublicIds.slice(i, i + 100);
            try {
                const deleteResult = await cloudinary.api.delete_resources(batch);
                const successfulDeletions = Object.values(deleteResult.deleted).filter(res => res === 'deleted').length;
                deletedCount += successfulDeletions;
                console.log(`Deleted ${successfulDeletions} images in batch...`);
            } catch (err) {
                console.error('Error deleting batch:', err.message);
                errorCount++;
            }
        }

        console.log(`\n✅ Cleanup complete!`);
        console.log(`- Successfully deleted: ${deletedCount}`);
        if (errorCount > 0) console.log(`- Batches with errors: ${errorCount}`);

    } catch (err) {
        console.error('❌ An unexpected error occurred:', err);
    }
}

runCleanup();

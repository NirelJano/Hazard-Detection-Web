# 🧹 Cloudinary Orphaned Image Cleanup Tool

This script finds and permanently deletes any images in your Cloudinary account that no longer have a corresponding report in your Firestore database.

Because this script deletes data, it runs **locally on your computer** and requires strong authentication to access your database. It reads your Cloudinary keys directly from your `.env` file.

## 🔑 Prerequisites: Getting your Firebase Service Account Key

To connect to your Firestore database securely from outside the browser, you need a Service Account Key.

1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Select your project: **`hazard-detection-web`**.
3. Click the ⚙️ (Gear Icon) next to **Project Overview** (top left) and select **Project settings**.
4. Go to the **Service accounts** tab.
5. Click the **Generate new private key** button at the bottom.
6. A `.json` file will be downloaded to your computer.
7. **Important:** Move that downloaded file into this `admin-tools` folder and rename it exactly to: **`serviceAccountKey.json`**.

> ⚠️ **SECURITY WARNING:** Never share `serviceAccountKey.json` or commit it to GitHub. It gives full administrative access to your entire Firebase project.

## 🚀 Running the script

Once your `serviceAccountKey.json` is in this folder, simply open your terminal, navigate to this folder, and run:

```bash
cd "admin-tools"
npm run cleanup
```

The script will:
1. Fetch all active reports from Firestore.
2. Fetch all stored images from Cloudinary.
3. Compare the two lists.
4. Delete any images from Cloudinary that don't exist in Firestore.

# Quick Setup Checklist ✅

Use this checklist to quickly set up your Hazard Detection app with all required backend services.

## 🎯 Prerequisites
- [ ] Xcode installed
- [ ] Internet connection
- [ ] Apple Developer account (free tier is fine)

---

## 1. Firebase Setup (Authentication & Database)

### Create Firebase Project
- [ ] Go to https://console.firebase.google.com/
- [ ] Click "Add project" or select existing project
- [ ] Follow the wizard to create project

### Add iOS App
- [ ] In Firebase Console, click "Add app" → iOS
- [ ] Enter your bundle ID (from Xcode project settings)
- [ ] Download `GoogleService-Info.plist`
- [ ] Drag `GoogleService-Info.plist` into Xcode project

### Enable Authentication
- [ ] In Firebase Console → Authentication → Sign-in method
- [ ] Enable "Email/Password"
- [ ] Click Save

### Create Firestore Database
- [ ] In Firebase Console → Firestore Database
- [ ] Click "Create database"
- [ ] Choose "Start in production mode"
- [ ] Select a region close to your users
- [ ] Click Enable

### Set Firestore Security Rules
- [ ] In Firestore → Rules tab
- [ ] Paste the following rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /reports/{reportId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null 
        && request.auth.uid == resource.data.userId;
    }
    match /profiles/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null 
        && request.auth.uid == userId;
    }
  }
}
```

- [ ] Click "Publish"

✅ **Firebase is now configured!**

---

## 2. Cloudinary Setup (Image Storage)

### Create Account
- [ ] Go to https://cloudinary.com/
- [ ] Sign up for free account
- [ ] Verify your email
- [ ] Log in to dashboard

### Get Cloud Name
- [ ] On dashboard, find "Cloud Name" (top left)
- [ ] Copy this value (e.g., `dcloud123abc`)
- [ ] Save it for later

### Create Upload Preset
- [ ] Click Settings (gear icon) → Upload
- [ ] Scroll to "Upload presets"
- [ ] Click "Add upload preset"
- [ ] **Important**: Set "Signing Mode" to **Unsigned**
- [ ] Give it a name (e.g., `hazard_detection_unsigned`)
- [ ] Click Save
- [ ] Copy the preset name

✅ **Cloudinary is now configured!**

---

## 3. Mapbox Setup (Geocoding)

### Create Account
- [ ] Go to https://www.mapbox.com/
- [ ] Sign up for free account
- [ ] Verify your email
- [ ] Log in to dashboard

### Create Access Token
- [ ] Go to Account → Tokens
- [ ] Click "Create a token"
- [ ] Name it (e.g., "Hazard Detection iOS")
- [ ] **Important**: Check the following scopes:
  - [ ] `styles:read`
  - [ ] `fonts:read`
  - [ ] `datasets:read`
  - [ ] `geocoding:read` ← **MUST HAVE THIS**
- [ ] Click "Create token"
- [ ] Copy the token (starts with `pk.`)

✅ **Mapbox is now configured!**

---

## 4. Configure Your Xcode Project

### Option A: Using xcconfig file (Recommended - Keeps secrets safe)

1. **Create Config File**
   - [ ] Copy `Config.xcconfig.template` to `Config.xcconfig`
   - [ ] Open `Config.xcconfig` in a text editor
   - [ ] Replace the placeholders with your actual values:

```
CLOUDINARY_CLOUD_NAME = your_cloud_name_here
CLOUDINARY_UPLOAD_PRESET = your_preset_name_here
MAPBOX_ACCESS_TOKEN = pk.your_actual_token_here
```

2. **Link Config to Xcode**
   - [ ] Open your project in Xcode
   - [ ] Select project file in Navigator
   - [ ] Select your target
   - [ ] Go to Info tab
   - [ ] Under "Configurations" → Debug → select `Config.xcconfig`
   - [ ] Do the same for Release

3. **Verify .gitignore**
   - [ ] Make sure `.gitignore` includes `Config.xcconfig`
   - [ ] This keeps your secrets out of Git

### Option B: Direct in Info.plist (Easier but less secure)

- [ ] Open `Info.plist` in Xcode
- [ ] Find these keys and replace the `$(...)` variables:

```xml
<key>CloudinaryCloudName</key>
<string>your_cloud_name_here</string>

<key>CloudinaryUploadPreset</key>
<string>your_preset_name_here</string>

<key>MapboxAccessToken</key>
<string>pk.your_actual_token_here</string>
```

⚠️ **Warning**: Don't commit actual tokens to Git!

✅ **Configuration is complete!**

---

## 5. Test Your Configuration

### Build and Run
- [ ] Clean build folder (Cmd+Shift+K)
- [ ] Build project (Cmd+B)
- [ ] Run on simulator or device (Cmd+R)

### Check Console Output
When the app launches, you should see:
```
==================================================
📊 BACKEND CONFIGURATION DIAGNOSTIC REPORT
==================================================

🔥 Firebase: ✅ Ready
   Details: Using GoogleService-Info.plist

☁️ Cloudinary: ✅ Ready
   Details: Cloud Name: ✓, Upload Preset: ✓

🗺️ Mapbox: ✅ Ready
   Details: Valid token format

--------------------------------------------------
✅ ALL SERVICES CONFIGURED - App is ready to use!
==================================================
```

### Check Settings Screen
- [ ] Run the app
- [ ] Create an account or sign in
- [ ] Navigate to Settings tab
- [ ] Under "System Info", verify all services show as configured:
  - [ ] 🔥 Firebase: ✅ Ready
  - [ ] ☁️ Cloudinary: ✅ Ready
  - [ ] 🗺️ Mapbox: ✅ Ready
  - [ ] 📍 Location: Allowed (after granting permission)

### Test Core Features
- [ ] **Authentication**: Sign up with email/password
- [ ] **Location**: Grant location permission when prompted
- [ ] **Image Upload**: Try uploading a hazard report with photo
- [ ] **Geocoding**: Verify address appears (not just coordinates)
- [ ] **Database**: Check if reports appear in feed

✅ **All features working!**

---

## 🎉 You're Done!

Your Hazard Detection app is now fully configured and ready to use.

### What You've Set Up:
- ✅ Firebase Authentication (user sign-in)
- ✅ Firestore Database (storing hazard reports)
- ✅ Cloudinary (image uploads)
- ✅ Mapbox (address lookup)

### Next Steps:
- Start testing the app
- Report bugs if you find any
- Customize the UI to your liking
- Deploy to TestFlight or App Store

---

## 🆘 Troubleshooting

### Problem: Firebase not working
**Solution**:
- Verify `GoogleService-Info.plist` is in project
- Check bundle ID matches Firebase console
- Make sure Authentication is enabled
- Verify Firestore database is created

### Problem: Images won't upload
**Solution**:
- Check Cloudinary cloud name is correct
- Verify upload preset is **unsigned**
- Make sure preset name matches exactly
- Check internet connection

### Problem: Addresses not showing
**Solution**:
- Verify Mapbox token has `geocoding:read` scope
- Token should start with `pk.`
- Check token isn't expired
- Grant location permissions

### Problem: "Not Configured" in Settings
**Solution**:
- Verify all values in Info.plist or Config.xcconfig
- Make sure no `$(...)` variables remain
- Clean and rebuild (Cmd+Shift+K, then Cmd+B)
- Check Xcode console for diagnostic report

---

## 📚 Additional Resources

- **Detailed Guide**: See `CONFIGURATION_DEBUG.md`
- **Code Reference**: Check `ConfigurationDiagnostics.swift`
- **Firebase Docs**: https://firebase.google.com/docs/ios/setup
- **Cloudinary Docs**: https://cloudinary.com/documentation/ios_integration
- **Mapbox Docs**: https://docs.mapbox.com/ios/maps/guides/

---

**Last Updated**: April 26, 2026
**Estimated Time**: 15-30 minutes for complete setup

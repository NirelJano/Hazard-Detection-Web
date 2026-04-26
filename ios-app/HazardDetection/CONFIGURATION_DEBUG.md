# Firebase, Cloudinary & Mapbox Configuration Debug Guide

## 🔧 Configuration Status Check

Your app integrates three critical backend services:
1. **Firebase** - Authentication & Firestore database
2. **Cloudinary** - Image upload and storage
3. **Mapbox** - Reverse geocoding (coordinates → addresses)

## 📋 Current Configuration Analysis

### ✅ Code Implementation Status
- ✅ Firebase initialized in `HazardDetectionApp.swift`
- ✅ CloudinaryService properly implemented
- ✅ GeocodingService (Mapbox) properly implemented
- ✅ Settings view shows configuration status
- ✅ All services use environment variables from Info.plist

### ⚠️ Configuration Requirements

## 1️⃣ FIREBASE SETUP

### Step 1: Download GoogleService-Info.plist
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (or create one)
3. Click on your iOS app
4. Download `GoogleService-Info.plist`
5. Add it to your Xcode project (drag & drop into project navigator)

### Step 2: Configure Info.plist (Optional - for custom config)
If you want to use environment variables instead of GoogleService-Info.plist:
```
FirebaseAPIKey = YOUR_FIREBASE_API_KEY
```

### Step 3: Enable Authentication
1. In Firebase Console → Authentication
2. Enable "Email/Password" sign-in method

### Step 4: Enable Firestore
1. In Firebase Console → Firestore Database
2. Create database in production mode
3. Update security rules:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /reports/{reportId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && request.auth.uid == resource.data.userId;
    }
    match /profiles/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### ✅ Firebase Debug Commands
Check if Firebase is configured:
- Open SettingsView in your app
- Look for "Firebase: Connected" or "Firebase: Not Configured"

---

## 2️⃣ CLOUDINARY SETUP

### Step 1: Create Cloudinary Account
1. Go to [Cloudinary](https://cloudinary.com/)
2. Sign up for free account
3. Note your **Cloud Name** from dashboard

### Step 2: Create Upload Preset
1. In Cloudinary Dashboard → Settings → Upload
2. Scroll to "Upload presets"
3. Click "Add upload preset"
4. Set **Signing Mode** to "Unsigned"
5. Name it (e.g., `hazard_detection_preset`)
6. Save

### Step 3: Configure Xcode Project
**Option A: Using xcconfig file (Recommended)**

Create `Config.xcconfig` file:
```
CLOUDINARY_CLOUD_NAME = your_cloud_name
CLOUDINARY_UPLOAD_PRESET = your_preset_name
```

Then in Xcode:
1. Select your project → Info tab
2. Under "Configurations" → Debug → select Config.xcconfig
3. Do the same for Release

**Option B: Direct in Info.plist**

Replace in Info.plist:
```xml
<key>CloudinaryCloudName</key>
<string>your_cloud_name</string>

<key>CloudinaryUploadPreset</key>
<string>your_preset_name</string>
```

### ✅ Cloudinary Debug Commands
Check if Cloudinary is configured:
- Open SettingsView in your app
- Look for "Cloudinary: Ready" or "Cloudinary: Not Configured"

---

## 3️⃣ MAPBOX SETUP

### Step 1: Create Mapbox Account
1. Go to [Mapbox](https://www.mapbox.com/)
2. Sign up for free account
3. Go to Account → Tokens

### Step 2: Create Access Token
1. Click "Create a token"
2. Name it (e.g., "Hazard Detection App")
3. Select these scopes:
   - `styles:read`
   - `fonts:read`
   - `datasets:read`
   - `geocoding:read` ← **IMPORTANT**
4. Copy the token

### Step 3: Configure Xcode Project
**Option A: Using xcconfig file (Recommended)**

Add to `Config.xcconfig`:
```
MAPBOX_ACCESS_TOKEN = pk.your_mapbox_token_here
```

**Option B: Direct in Info.plist**

Replace in Info.plist:
```xml
<key>MapboxAccessToken</key>
<string>pk.your_mapbox_token_here</string>
```

### ✅ Mapbox Debug Commands
Check if Mapbox is configured:
- Open SettingsView in your app
- Look for "Mapbox: Active" or "Mapbox: Not Configured"

---

## 🚀 QUICK START GUIDE

### Method 1: Using xcconfig (Recommended for security)

1. Create `Config.xcconfig` in your project root:
```
// Config.xcconfig
FIREBASE_API_KEY = AIzaSy...
CLOUDINARY_CLOUD_NAME = your_cloud_name
CLOUDINARY_UPLOAD_PRESET = your_preset
MAPBOX_ACCESS_TOKEN = pk.eyJ1...
```

2. Add `.xcconfig` to .gitignore:
```
# .gitignore
Config.xcconfig
*.xcconfig
```

3. In Xcode:
   - Project → Info tab
   - Under Configurations → set Config.xcconfig for Debug & Release

4. Info.plist already uses variables:
```xml
<key>CloudinaryCloudName</key>
<string>$(CLOUDINARY_CLOUD_NAME)</string>
```

### Method 2: Direct Configuration (Easier, less secure)

Edit Info.plist and replace the `$(...)` variables with your actual values:

```xml
<key>CloudinaryCloudName</key>
<string>dxyz123abc</string>

<key>CloudinaryUploadPreset</key>
<string>hazard_preset</string>

<key>MapboxAccessToken</key>
<string>pk.eyJ1IjoieW91cnVzZXJuYW1lIiwiYSI6ImNrNzg5...</string>
```

⚠️ **Security Note**: Don't commit actual tokens to Git!

---

## 🧪 TESTING YOUR CONFIGURATION

### Test Firebase
1. Run app
2. Try to sign in/create account
3. Check Settings → "Firebase: Connected"

### Test Cloudinary
1. Run app
2. Sign in
3. Try to upload a hazard report with an image
4. Check Settings → "Cloudinary: Ready"

### Test Mapbox
1. Run app
2. Enable location services
3. Upload a report with location
4. The address should appear (not just coordinates)
5. Check Settings → "Mapbox: Active"

---

## 🐛 TROUBLESHOOTING

### Firebase Not Working
- ✅ Check `GoogleService-Info.plist` is in project
- ✅ Verify bundle ID matches Firebase console
- ✅ Enable Email/Password authentication
- ✅ Create Firestore database

### Cloudinary Upload Fails
- ✅ Verify cloud name is correct (no typos)
- ✅ Verify upload preset is **unsigned**
- ✅ Check preset name matches exactly
- ✅ Check network connection

### Mapbox Geocoding Fails
- ✅ Verify token has `geocoding:read` scope
- ✅ Token should start with `pk.`
- ✅ Check token isn't expired
- ✅ Verify location permissions granted

### "Not Configured" in Settings
- ✅ Check Info.plist has all keys
- ✅ Values don't contain `$(...)` variables
- ✅ Values aren't empty strings
- ✅ Clean build folder (Cmd+Shift+K)
- ✅ Rebuild project (Cmd+B)

---

## 📱 Where to Check Status

Your app has a built-in configuration checker!

1. Run the app
2. Sign in
3. Navigate to **Settings** tab
4. Look under "System Info":
   - Firebase: Should say "Connected"
   - Cloudinary: Should say "Ready"
   - Mapbox: Should say "Active"
   - Location: Should say "Allowed" (after granting permission)

---

## 🔑 Environment Variables Reference

Here's what needs to be configured:

| Service | Key | Example Value | Required |
|---------|-----|---------------|----------|
| Firebase | `FirebaseAPIKey` | `AIzaSyC...` | Optional* |
| Cloudinary | `CloudinaryCloudName` | `dcloud123` | Yes |
| Cloudinary | `CloudinaryUploadPreset` | `hazard_preset` | Yes |
| Mapbox | `MapboxAccessToken` | `pk.eyJ1...` | Yes |

*Optional if using GoogleService-Info.plist

---

## 📝 Next Steps

1. ✅ Add Info.plist to your Xcode project
2. ⬜ Set up Firebase (download GoogleService-Info.plist)
3. ⬜ Set up Cloudinary (get cloud name & preset)
4. ⬜ Set up Mapbox (get access token)
5. ⬜ Configure values in Info.plist or xcconfig
6. ⬜ Run app and check Settings view
7. ⬜ Test uploading a hazard report

---

## 🎯 Success Criteria

Your configuration is complete when:
- ✅ Settings shows all services as configured
- ✅ You can sign in with email/password
- ✅ You can upload hazard reports with images
- ✅ Address appears correctly (not just coordinates)
- ✅ No error messages in Xcode console

---

## 💡 Pro Tips

1. **Use xcconfig for security** - Keep tokens out of Git
2. **Check Settings view first** - Built-in diagnostics
3. **Enable all location permissions** - For best UX
4. **Test image upload early** - Cloudinary config is critical
5. **Monitor Xcode console** - Services print debug info

---

Need more help? Check the individual service files:
- `HazardDetectionApp.swift` - Firebase initialization
- `CloudinaryService.swift` - Image upload logic
- `GeocodingService.swift` - Mapbox reverse geocoding
- `SettingsView.swift` - Configuration status display

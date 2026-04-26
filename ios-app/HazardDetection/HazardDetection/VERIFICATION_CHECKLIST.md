# ✅ Setup Verification - What You've Done

## Status Check

### ✅ Completed
- [x] GoogleService-Info.plist added to project

### ⏳ Still Need to Verify

Please confirm you've completed these steps:

## 1️⃣ Info.plist Configuration

Have you added the Cloudinary and Mapbox keys to your **existing** Info.plist?

You should have added these keys:

```xml
<key>CloudinaryCloudName</key>
<string>dhw2qum65</string>

<key>CloudinaryUploadPreset</key>
<string>Road_Hazard_Detection_WEB</string>

<key>MapboxAccessToken</key>
<string>YOUR_MAPBOX_PUBLIC_TOKEN</string>
```

**How to verify:**
1. Open Info.plist in Xcode
2. Look for these three keys
3. Make sure the values match exactly

---

## 2️⃣ Firebase Console Setup

Have you completed these in Firebase Console?

### Authentication
- [ ] Go to https://console.firebase.google.com/
- [ ] Select your project
- [ ] Click **Authentication** → **Get Started**
- [ ] Go to **Sign-in method** tab
- [ ] Enable **Email/Password**
- [ ] Click **Save**

### Firestore Database
- [ ] Click **Firestore Database** → **Create database**
- [ ] Choose **Start in production mode** (we'll set rules next)
- [ ] Select a region
- [ ] Click **Enable**

### Firestore Security Rules
- [ ] In Firestore, go to **Rules** tab
- [ ] Delete existing rules and paste these:

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

- [ ] Click **Publish**

---

## 3️⃣ Test Your Setup

### Build and Run
```bash
# In Xcode:
Cmd+Shift+K  # Clean build folder
Cmd+B        # Build
Cmd+R        # Run
```

### Check Settings Screen

When you run the app and navigate to the **Settings** tab, you should see:

```
System Info
🔥 Firebase        ✅ Ready
☁️ Cloudinary      ✅ Ready
🗺️ Mapbox          ✅ Ready
📍 Location        (Allowed after you grant permission)
```

### What Each Status Means

**🔥 Firebase: ✅ Ready**
- ✅ GoogleService-Info.plist is in your project
- ✅ Firebase is initialized correctly

**☁️ Cloudinary: ✅ Ready**
- ✅ CloudinaryCloudName is in Info.plist
- ✅ CloudinaryUploadPreset is in Info.plist
- ✅ No placeholder values like $(...)

**🗺️ Mapbox: ✅ Ready**
- ✅ MapboxAccessToken is in Info.plist
- ✅ Token starts with "pk."
- ✅ No placeholder values

---

## 🐛 Troubleshooting

### If Firebase Shows "❌ Not Configured"
**Problem**: GoogleService-Info.plist not found or not in target

**Solution**:
1. Find GoogleService-Info.plist in Xcode's Project Navigator
2. Click on it
3. Open **File Inspector** (right panel)
4. Make sure your app target is checked under "Target Membership"

### If Cloudinary Shows "❌ Not Configured"
**Problem**: Keys not in Info.plist or have typos

**Solution**:
1. Open Info.plist in Xcode
2. Click the `+` button to add a key
3. Type exactly: `CloudinaryCloudName`
4. Value: `dhw2qum65`
5. Click `+` again
6. Type exactly: `CloudinaryUploadPreset`
7. Value: `Road_Hazard_Detection_WEB`

**Or use the paste method:**
1. Right-click Info.plist → Open As → Source Code
2. Copy from `PASTE_INTO_INFO_PLIST.xml`
3. Paste before `</dict>`

### If Mapbox Shows "❌ Not Configured"
**Problem**: Token not in Info.plist or incomplete

**Solution**:
1. Open Info.plist
2. Add key: `MapboxAccessToken`
3. Value: `YOUR_MAPBOX_PUBLIC_TOKEN`
4. Make sure the entire token is copied (it's very long!)

---

## 📋 Quick Checklist

Before you test, make sure:

- [x] GoogleService-Info.plist in Xcode project ✅ (You did this!)
- [ ] GoogleService-Info.plist included in target
- [ ] Info.plist has CloudinaryCloudName = `dhw2qum65`
- [ ] Info.plist has CloudinaryUploadPreset = `Road_Hazard_Detection_WEB`
- [ ] Info.plist has MapboxAccessToken = YOUR_MAPBOX_PUBLIC_TOKEN
- [ ] Firebase Authentication enabled (Email/Password)
- [ ] Firestore Database created
- [ ] Firestore Security Rules published

---

## 🚀 Next Actions

### If you haven't updated Info.plist yet:
1. Open `PASTE_INTO_INFO_PLIST.xml`
2. Copy all content
3. Right-click Info.plist → Open As → Source Code
4. Paste before `</dict>` tag
5. Save

### If you haven't set up Firebase Console:
1. Go to https://console.firebase.google.com/
2. Select your project
3. Enable Authentication (Email/Password)
4. Create Firestore Database
5. Set security rules (copy from above)

### Then test:
```bash
Cmd+Shift+K  # Clean
Cmd+R        # Run
```

Check Settings tab for ✅ Ready on all services!

---

## ✅ Success Criteria

You'll know everything is working when:

1. **App builds without errors** ✅
2. **Settings shows all Ready** ✅
3. **You can create an account** ✅
4. **You can upload a hazard with image** ✅
5. **Address appears (not coordinates)** ✅

---

**What to do now:**

1. If you haven't added Cloudinary/Mapbox keys to Info.plist → Do that first
2. Set up Firebase Console (Authentication + Firestore + Rules)
3. Clean and run
4. Check Settings screen
5. Test creating account and uploading

**Need the exact keys to add?** Open `PASTE_INTO_INFO_PLIST.xml` - everything is ready to copy!

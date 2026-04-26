# Configuration Flow Diagram

## 🔄 How Configuration Works

```
┌─────────────────────────────────────────────────────────────┐
│                    YOUR CONFIGURATION                        │
│                                                              │
│  Option 1: Config.xcconfig     Option 2: Info.plist        │
│  ┌──────────────────┐          ┌──────────────────┐        │
│  │ CLOUD_NAME=abc   │    OR    │ <key>Cloud...</>  │        │
│  │ PRESET=xyz       │          │ <string>abc</>    │        │
│  │ TOKEN=pk.123     │          │ ...               │        │
│  └──────────────────┘          └──────────────────┘        │
│           ↓                              ↓                   │
│           └──────────────┬───────────────┘                   │
│                          ↓                                   │
│                    Info.plist                                │
│         $(CLOUD_NAME) or hardcoded values                   │
└──────────────────────────┬───────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                  APP LAUNCH SEQUENCE                         │
│                                                              │
│  1. HazardDetectionApp.swift                                │
│     └─ AppDelegate.application(_:didFinishLaunching...)     │
│        ├─ FirebaseApp.configure()          [Firebase ✅]    │
│        └─ ConfigurationDiagnostics.debugPrintStatus()       │
│                          ↓                                   │
│  2. ConfigurationDiagnostics                                │
│     ├─ checkFirebase()                     [🔥 Check]       │
│     ├─ checkCloudinary()                   [☁️ Check]       │
│     └─ checkMapbox()                       [🗺️ Check]       │
│                          ↓                                   │
│  3. Print Console Report                                    │
│     ╔════════════════════════════════════════════╗          │
│     ║ 📊 BACKEND CONFIGURATION DIAGNOSTIC        ║          │
│     ╠════════════════════════════════════════════╣          │
│     ║ 🔥 Firebase: ✅ Ready                      ║          │
│     ║ ☁️ Cloudinary: ✅ Ready                    ║          │
│     ║ 🗺️ Mapbox: ✅ Ready                        ║          │
│     ║ ✅ ALL SERVICES CONFIGURED                 ║          │
│     ╚════════════════════════════════════════════╝          │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    RUNTIME USAGE                             │
│                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │ AuthManager     │  │CloudinaryService│  │GeocodingServ│ │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────┤ │
│  │ Uses Firebase   │  │ Reads Info.plist│  │Reads Mapbox │ │
│  │ for Auth        │  │ for cloud name  │  │token        │ │
│  │                 │  │ & preset        │  │             │ │
│  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│          ↓                     ↓                    ↓        │
│  Sign in/Sign up    Upload hazard image    Get address      │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                    USER INTERFACE                            │
│                                                              │
│  SettingsView (Shows Configuration Status)                  │
│  ┌────────────────────────────────────────────────────┐    │
│  │ System Info                                    ℹ️   │    │
│  ├────────────────────────────────────────────────────┤    │
│  │ 🔥 Firebase           ✅ Ready                     │    │
│  │ ☁️ Cloudinary         ✅ Ready                     │    │
│  │ 🗺️ Mapbox             ✅ Ready                     │    │
│  │ 📍 Location           Allowed                      │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  Tap ℹ️ → Prints diagnostic report to console              │
└─────────────────────────────────────────────────────────────┘
```

## 📊 Service Flow Diagrams

### Firebase Authentication Flow
```
User taps "Sign Up"
       ↓
AuthManager.signUp(email:password:)
       ↓
Firebase Auth (configured via GoogleService-Info.plist)
       ↓
Creates user account
       ↓
Returns User object
       ↓
Creates profile in Firestore
       ↓
User signed in ✅
```

### Cloudinary Upload Flow
```
User selects hazard image
       ↓
UploadReportView
       ↓
ReportRepository.addReport(image:...)
       ↓
CloudinaryService.uploadImage()
       ├─ Reads CloudinaryCloudName from Info.plist
       ├─ Reads CloudinaryUploadPreset from Info.plist
       └─ Uploads to https://api.cloudinary.com/v1_1/{cloudName}/image/upload
       ↓
Returns secure_url (https://res.cloudinary.com/...)
       ↓
Saves URL to Firestore
       ↓
Image uploaded ✅
```

### Mapbox Geocoding Flow
```
User's location obtained (CLLocationCoordinate2D)
       ↓
GeocodingService.reverseGeocode(coordinate:)
       ├─ Reads MapboxAccessToken from Info.plist
       └─ Calls https://api.mapbox.com/search/geocode/v6/reverse
       ↓
Returns JSON with address
       ↓
Parses "full_address" from response
       ↓
Returns address string
       ↓
Displayed in UI ✅
```

## 🔐 Configuration Security Flow

### Development (Recommended)
```
1. Developer creates Config.xcconfig
   CLOUDINARY_CLOUD_NAME = abc123
   MAPBOX_ACCESS_TOKEN = pk.xyz789

2. File added to .gitignore
   ✅ Not committed to Git

3. Xcode Project → Configurations
   Debug → Config.xcconfig
   Release → Config.xcconfig

4. Info.plist references variables
   <string>$(CLOUDINARY_CLOUD_NAME)</string>

5. Build time: Xcode replaces variables
   $(CLOUDINARY_CLOUD_NAME) → abc123

6. Runtime: App reads from Info.plist
   Bundle.main.object(forInfoDictionaryKey: "CloudinaryCloudName")
   → "abc123" ✅
```

### Team Collaboration
```
Developer A                    Developer B
     ↓                              ↓
Config.xcconfig                Config.xcconfig
(personal keys)                (personal keys)
     ↓                              ↓
.gitignore excludes            .gitignore excludes
     ↓                              ↓
Git Repository (shared)
     │
     ├─ Info.plist (variables only)
     ├─ Config.xcconfig.template
     └─ .gitignore
     ↓
Both developers have different keys
but same codebase ✅
```

## 🧪 Diagnostic Check Flow

```
App Launch (Debug)
       ↓
ConfigurationDiagnostics.debugPrintStatus()
       ↓
┌──────────────────────────────────────┐
│ For each service:                    │
│                                      │
│ 1. Read from Bundle.main             │
│    ↓                                 │
│ 2. Check if value exists             │
│    ↓                                 │
│ 3. Check if not empty                │
│    ↓                                 │
│ 4. Check for placeholders            │
│    - $(...)                          │
│    - YOUR_...                        │
│    - REPLACE_...                     │
│    ↓                                 │
│ 5. Special validation                │
│    - Firebase: Check for plist       │
│    - Mapbox: Check pk./sk. prefix    │
│    ↓                                 │
│ 6. Create ServiceStatus              │
│    - name, isConfigured, details     │
└──────────────────────────────────────┘
       ↓
Print formatted report
       ↓
Console shows status ✅
```

## 📱 User Interaction Flow

```
User opens app
       ↓
       ├─ First time?
       │  Yes → AuthenticationView
       │         ↓
       │         Sign Up / Sign In
       │         ↓
       │         Firebase Auth ✅
       │
       └─ Already signed in?
          Yes → MainTabView
                ↓
                ┌───────┬───────┬──────────┐
                ↓       ↓       ↓          ↓
             Reports  Camera  Upload   Settings
                              ↓          ↓
                         Select Image   System Info
                              ↓          ↓
                         Cloudinary ✅  Diagnostics ✅
                              ↓
                         Get Location
                              ↓
                         Mapbox ✅
                              ↓
                         Save to Firestore ✅
```

## 🔄 Complete Request Flow Example

### Uploading a Hazard Report
```
1. User Flow
   User taps camera → Takes photo → Fills description → Taps Submit

2. Data Preparation
   UIImage → Location → Description → Type

3. Image Upload (Cloudinary)
   CloudinaryService.uploadImage(image)
   ↓
   POST https://api.cloudinary.com/v1_1/{cloudName}/image/upload
   ↓
   Returns: https://res.cloudinary.com/{cloudName}/image/upload/v123/abc.jpg

4. Address Lookup (Mapbox)
   GeocodingService.reverseGeocode(coordinate)
   ↓
   GET https://api.mapbox.com/search/geocode/v6/reverse?...
   ↓
   Returns: "123 Main St, San Francisco, CA 94102"

5. Save to Database (Firebase)
   Firestore.collection("reports").addDocument([
     type: "pothole",
     imageUrl: "https://res.cloudinary.com/...",
     address: "123 Main St...",
     userId: "firebase_user_id",
     ...
   ])

6. Update UI
   ReportRepository publishes new reports
   ↓
   ContentView updates
   ↓
   User sees new report in feed ✅
```

## 🎯 Configuration Validation

```
┌─────────────────────────────────────┐
│   isValidConfigValue() checks:      │
├─────────────────────────────────────┤
│                                     │
│  ✅ Not nil                         │
│  ✅ Not empty string                │
│  ✅ Doesn't contain "$("            │
│  ✅ Doesn't contain "YOUR_"         │
│  ✅ Doesn't contain "REPLACE_"      │
│  ✅ Doesn't contain "PLACEHOLDER"   │
│                                     │
│  For Mapbox:                        │
│  ✅ Starts with "pk." or "sk."      │
│                                     │
│  For Firebase:                      │
│  ✅ GoogleService-Info.plist exists │
│  OR                                 │
│  ✅ FirebaseAPIKey in Info.plist    │
└─────────────────────────────────────┘
```

## 📈 Success Path

```
Developer Journey:

1. Receives code ✅
   ↓
2. Reads BACKEND_SETUP_README.md
   ↓
3. Follows SETUP_CHECKLIST.md
   ↓
   ├─ Creates Firebase project
   ├─ Downloads GoogleService-Info.plist
   ├─ Creates Cloudinary account
   ├─ Gets cloud name & preset
   ├─ Creates Mapbox account
   └─ Gets access token
   ↓
4. Chooses configuration method
   ├─ Option A: Creates Config.xcconfig
   └─ Option B: Edits Info.plist
   ↓
5. Runs app
   ↓
6. Checks console output
   "✅ ALL SERVICES CONFIGURED"
   ↓
7. Opens Settings in app
   All services show ✅ Ready
   ↓
8. Tests features
   ├─ Sign up ✅
   ├─ Upload report with image ✅
   └─ Address appears ✅
   ↓
9. App fully functional! 🎉
```

---

**Visual Guide Created**: April 26, 2026
**Purpose**: Help developers understand configuration flow
**Recommended**: Print this for reference during setup

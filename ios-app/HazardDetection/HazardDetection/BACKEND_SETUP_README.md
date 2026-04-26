# 🔧 Backend Configuration Guide

This guide helps you configure Firebase, Cloudinary, and Mapbox for the Hazard Detection app.

## 📁 Files Created

I've created several files to help you configure your backend services:

1. **`Info.plist`** - Main configuration file with all required keys
2. **`SETUP_CHECKLIST.md`** - Step-by-step setup instructions ⭐ **START HERE**
3. **`CONFIGURATION_DEBUG.md`** - Detailed troubleshooting guide
4. **`Config.xcconfig.template`** - Template for secure configuration
5. **`ConfigurationDiagnostics.swift`** - Automatic configuration checker
6. **`.gitignore`** - Protects your API keys from being committed

## 🚀 Quick Start

### Option 1: Quick Setup (15-30 minutes)
Follow the **`SETUP_CHECKLIST.md`** file for a step-by-step guide.

### Option 2: Automated Diagnostics
1. Run your app
2. Check the Xcode console for the diagnostic report
3. Go to Settings tab in the app to see configuration status

## ✅ What Was Fixed

### 1. Updated Info.plist
- ✅ Added interface orientation support (fixes your warning)
- ✅ Added placeholders for Firebase, Cloudinary, and Mapbox
- ✅ Added privacy descriptions for Location, Camera, and Photos

### 2. Enhanced SettingsView
- ✅ Now uses `ConfigurationDiagnostics` for better status checking
- ✅ Shows emoji indicators for each service
- ✅ Tap ℹ️ button to print diagnostic report
- ✅ Shows warning if services aren't configured

### 3. Added Diagnostic Tool
- ✅ `ConfigurationDiagnostics.swift` checks all services automatically
- ✅ Prints detailed report on app launch (Debug builds only)
- ✅ Validates configuration values
- ✅ Checks for common mistakes (placeholders, empty values, etc.)

### 4. Updated HazardDetectionApp
- ✅ Now runs diagnostics on app launch in Debug mode
- ✅ Helps you identify configuration issues immediately

## 📋 What You Need to Configure

You need to set up three backend services:

| Service | Purpose | Required |
|---------|---------|----------|
| **Firebase** | User authentication & database | ✅ Yes |
| **Cloudinary** | Image upload and storage | ✅ Yes |
| **Mapbox** | Address lookup from coordinates | ✅ Yes |

## 🎯 Configuration Methods

### Method 1: xcconfig (Recommended - Most Secure)

**Pros**: 
- Keeps secrets out of Git
- Easy to manage multiple environments
- Industry best practice

**How to use**:
1. Copy `Config.xcconfig.template` to `Config.xcconfig`
2. Add your actual API keys to `Config.xcconfig`
3. Link to Xcode: Project → Info → Configurations
4. File is already in `.gitignore` - safe to commit

### Method 2: Direct in Info.plist (Easier)

**Pros**:
- Simple and straightforward
- No extra configuration needed

**Cons**:
- API keys visible in repository
- Need to be careful with Git commits

**How to use**:
1. Open `Info.plist`
2. Replace all `$(...)` variables with actual values
3. ⚠️ Do NOT commit this file with real keys!

## 📊 How to Check Configuration

### During Development
The app automatically prints a diagnostic report when launched in Debug mode:

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

### In the App
1. Launch the app
2. Sign in
3. Go to **Settings** tab
4. Check "System Info" section
5. Tap ℹ️ to print detailed report to console

## 🐛 Troubleshooting

### "All services show as Not Configured"
- Check that you've replaced the `$(...)` placeholders
- Verify Info.plist has all three services configured
- Clean build folder and rebuild

### "Firebase: Not Configured"
- Make sure `GoogleService-Info.plist` is in your project
- Or add `FirebaseAPIKey` to Info.plist
- Check bundle ID matches Firebase console

### "Cloudinary: Not Configured"
- Verify cloud name is correct (no typos)
- Check upload preset exists and is **unsigned**
- Make sure both values are in Info.plist

### "Mapbox: Not Configured"
- Verify token starts with `pk.` or `sk.`
- Check token has `geocoding:read` scope
- Make sure token isn't expired

## 📚 Documentation

- **Quick Setup**: `SETUP_CHECKLIST.md` ⭐ Start here
- **Detailed Guide**: `CONFIGURATION_DEBUG.md`
- **Code Reference**: `ConfigurationDiagnostics.swift`

## 🎉 Success Criteria

Your configuration is complete when:
- ✅ Xcode console shows "ALL SERVICES CONFIGURED"
- ✅ Settings screen shows all services with ✅ Ready
- ✅ You can create an account and sign in
- ✅ You can upload hazard reports with images
- ✅ Addresses appear correctly (not just coordinates)
- ✅ No error messages in console

## 📞 Next Steps

1. Follow the `SETUP_CHECKLIST.md` guide
2. Configure all three services
3. Run the app and check diagnostics
4. Test core features (auth, upload, geocoding)
5. Start building your hazard detection app!

---

**Need Help?** Check `CONFIGURATION_DEBUG.md` for detailed troubleshooting steps.

**Ready to Start?** Open `SETUP_CHECKLIST.md` and follow along! 🚀

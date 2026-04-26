## Firebase iOS Config

The app expects a local Firebase config file at:

`ios-app/HazardDetection/HazardDetection/GoogleService-Info.plist`

Do not commit that file.

To set up locally:

1. Open the Firebase console for the iOS app.
2. Download `GoogleService-Info.plist`.
3. Place it at the path above.

The file is ignored by git because GitHub secret scanning may flag the API key it contains.

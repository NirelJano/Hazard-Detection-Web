# CLAUDE.md — iOS Hazard Detection

Guidance for Claude Code (claude.ai/code) working on the native SwiftUI app under `ios-app/HazardDetection/`. This file complements `ios-app/AGENTS.md` (general repo conventions) with iOS-specific architecture and the in-progress upgrade context.

## Commands

```sh
cd ios-app/HazardDetection
python3 generate_project.py                                                     # regen HazardDetection.xcodeproj from project.yml
xcodebuild -project HazardDetection.xcodeproj -scheme HazardDetection \
  -destination 'platform=iOS Simulator,name=iPhone 15' build                    # simulator build smoke
xcodebuild -project HazardDetection.xcodeproj -scheme HazardDetection \
  -destination 'platform=iOS Simulator,name=iPhone 15' test                     # tests (target may not exist yet — see roadmap)
```

## Architecture

**Single SwiftUI target** — `HazardDetectionApp.swift` boots Firebase, then hands off to `ContentView` which gates on `AuthManager` and presents either `AuthenticationView` or `MainTabView` (4 tabs: Dashboard, Live Detection, Upload Report, Settings).

**Live detection pipeline** — `CameraManager.swift` owns the `AVCaptureSession`, throttles inference to every 0.25s, and runs Vision/`VNCoreMLRequest` against the compiled `best.mlmodelc` (YOLOv8 head, 80 classes, 640×640 RGB input). Results flow through `DetectionTracker` (`BackendServices.swift:506-623`), an IoU-matching state machine with velocity prediction, and `LiveDetectionView` renders bounding boxes via `CameraView` at 60 FPS with EMA smoothing.

**Auto-report trigger** — A track is auto-reported when `state == .vanished && age > 15 && bottom 40% of image` (`BackendServices.swift:591-597,660-663`). `AppController.submitLiveReport` (`345`) applies a 10-second per-label throttle (`444-447`) and a 5m/30s spatial+temporal dedupe (`449-463`) before writing to Firestore.

**Backend stack** — Firebase Auth (email/password), Firestore (`reports`, `users`, `metadata` collections — same shape as the web app), Cloudinary for image storage (multipart unsigned upload via preset), Mapbox for reverse geocoding, MapKit for native map UI. Configuration is read from `Info.plist` keys; `ConfigurationDiagnostics.swift` prints a readiness report at launch.

**Shared Firestore schema with web** — `Models.swift::HazardReport` matches the schema in `/PROJECT_SPEC.md`. iOS adds detection metadata fields: `detectedLabel`, `detectionConfidence`, `detectionSource ("manual_image"|"live_camera")`, `detectionBoundingBox`. When changing the schema, update both clients and the spec.

## Active upgrade work

The live-detection and report-creation flows are mid-upgrade. **Before modifying any of the files below, read `docs/UPGRADE_ROADMAP.md` and the relevant milestone doc.**

| Milestone | Touches |
| --- | --- |
| M1 (offline reliability) | `BackendServices.swift`, `CloudinaryService.swift`, `HazardDetectionApp.swift`, new `Persistence/` + `Networking/` packages |
| M2 (multi-class + threshold UI) | `CameraManager.swift`, `BackendServices.swift` (DetectionTracker), `SettingsView.swift`, new `Detection/` package |
| M3 (live UX) | `LiveDetectionView.swift`, `BackendServices.swift` (AppController), `UIComponents.swift`, new `Live/` package |
| M4 (performance) | `CameraManager.swift`, `CameraView.swift`, `LiveDetectionView.swift`, `BackendServices.swift` (DetectionGeometry), new `Performance/` package |
| M5 (manual uploads) | `UploadReportView.swift`, `CloudinaryService.swift`, `BackendServices.swift`, new `Upload/` package |
| M6 (sync polish) | `BackendServices.swift`, `SettingsView.swift`, `HazardDetectionApp.swift`, `Info.plist`, new `Background/` package |

## Conventions

- **iOS deployment target**: 17.0 (set in `project.yml` and `HazardDetection.xcodeproj`). Use SwiftData, `@Observable`, `MapKit.Map` with `MapCameraPosition`, async/await idioms freely.
- **Persistence**: SwiftData. Do not introduce CoreData.
- **Networking**: every Cloudinary upload routes through the M1 `BackgroundUploadCoordinator` once it lands. Until then, do not add new in-process upload paths — extend `CloudinaryService` cleanly so M1 can adopt it.
- **Idempotency**: every report write must include `clientReportId` (UUID). Firestore commit is keyed by it.
- **Threading**: `ReportRepository`, `AuthManager`, `LocationManager` are `@MainActor`. Inference runs off-main inside `CameraManager`'s session queue. Do not break this boundary.
- **No hardcoded label maps**: load class labels from `MLModelDescription.classLabels` with a `labels.json` fallback (M2 contract). Do not extend the switch at `CameraManager.swift:56-62` — it's being deleted.
- **Reuse before rewrite**: `DetectionTracker`, `ReportRepository`, `AppController`, `ImageAnnotator`, `DetectionGeometry`, `GeocodingService`, `ConfigurationDiagnostics` are the seams. Extend in place.
- **Commit style**: conventional prefixes (`feat:`, `refactor:`, `fix:`, `docs:`) with concise imperative summaries. Mirror existing history.
- **Doc updates**: when a milestone progresses, flip the `Status:` line at the top of its `docs/milestones/Mx-*.md` (`planned` → `in-progress` → `shipped`).

## Configuration files

- `Info.plist` — permission strings (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSPhotoLibraryUsageDescription`), Cloudinary/Mapbox keys, and (post-M6) `BGTaskSchedulerPermittedIdentifiers`.
- `Config.xcconfig.template`, `Secrets.xcconfig.example` — keep populated values out of git; refer to `CONFIGURATION_DEBUG.md` and `FIREBASE_SETUP.md`.
- `GoogleService-Info.plist` — required for Firebase; not committed.

## When working on this app

1. Identify which milestone your change belongs to. If it touches roadmap files, read that milestone doc first.
2. Run `python3 generate_project.py` after changing `project.yml`.
3. Build for the iPhone 15 simulator before opening review.
4. If changing Firestore schema, also update `/PROJECT_SPEC.md` and coordinate with the web client.
5. If a change is out of roadmap scope, say so explicitly and propose an addition rather than silently widening it.

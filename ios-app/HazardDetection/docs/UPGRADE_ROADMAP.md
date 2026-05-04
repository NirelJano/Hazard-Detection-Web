# iOS Hazard Detection — Live Detection & Reports Upgrade Roadmap

## Why this exists

The native SwiftUI app at `ios-app/HazardDetection/HazardDetection/` already runs a complete live-detection + auto-report pipeline (AVFoundation → Vision/Core ML YOLOv8 → IoU tracker → Cloudinary + Firestore). It works on the happy path, but loses reports when the network drops, exposes only 2 of 80 model classes, hardcodes confidence thresholds, has no haptic/undo feedback on auto-submitted reports, runs portrait-only despite `Info.plist` allowing all orientations, and ignores thermal/low-power state.

This roadmap turns the existing well-architected app into a production-grade field tool by closing those gaps in six independently-shippable milestones, prioritising offline reliability first because every other improvement assumes reports actually reach Firestore.

## Scope

Covers all eight focus areas across live detection and reports:

**Live detection**
- Reliability — offline queue, retry, reachability
- Detection quality — multi-class, tracker tuning, threshold UI
- Live UX — HUD, haptics, recent reports, undo
- Performance — battery/thermal, adaptive FPS, landscape

**Report creation**
- Robust uploads — adaptive compression, background URLSession, progress
- Persistence & sync — SwiftData queue + Firestore listener reconciliation
- Manual fallbacks — manual location pin, hazard-type override, photo source
- Editable review step before submit

## Architectural decisions (apply to every milestone)

- **Persistence**: SwiftData. Deployment target is iOS 17 (`HazardDetection.xcodeproj` → `IPHONEOS_DEPLOYMENT_TARGET=17.0`), so we get `@Model` value-types, native `@MainActor` integration, and `ModelContext` undo without CoreData boilerplate.
- **Background uploads**: `URLSessionConfiguration.background(withIdentifier: "com.hazard.uploads")` owned by a singleton `BackgroundUploadCoordinator`. Cloudinary upload runs via background session; Firestore commit happens in the `urlSession(_:task:didCompleteWithError:)` callback. App-relaunch hook in `HazardDetectionApp.swift` reattaches the session by identifier.
- **Multi-class labels**: read `MLModelDescription.classLabels` from the compiled `best.mlmodelc` at `HazardDetector.init`, fall back to bundled `labels.json`. Avoids drift between retrained models and the hardcoded map at `CameraManager.swift:56-62`.
- **Idempotency**: every queued report carries a client-generated `clientReportId` (UUID) used as the Firestore dedupe key, so retries after a partial failure never double-write.
- **Reuse over rewrite**: extend `DetectionTracker` (`BackendServices.swift:506-623`), `ReportRepository` (`30-218`), `AppController` (`220-464`), `ImageAnnotator`/`DetectionGeometry` (`666-759`). No parallel state systems.

## Critical files

| Path | Role |
| --- | --- |
| `HazardDetection/BackendServices.swift` | ReportRepository, AppController, DetectionTracker, ImageAnnotator, DetectionGeometry |
| `HazardDetection/CameraManager.swift` | AVFoundation + Vision pipeline, label normalization, threshold logic |
| `HazardDetection/CameraView.swift` | UIViewRepresentable preview + bbox overlay |
| `HazardDetection/LiveDetectionView.swift` | Live UI, HUD, render loop |
| `HazardDetection/UploadReportView.swift` | Manual upload flow |
| `HazardDetection/CloudinaryService.swift` | Multipart upload (no retry today) |
| `HazardDetection/Models.swift` | `HazardReport` schema |
| `HazardDetection/HazardDetectionApp.swift` | App entry, Firebase init (background-session reattach hook needed) |

## Milestones at a glance

| ID | Title | Complexity | Detail |
| --- | --- | --- | --- |
| M1 | Offline reliability foundation | L | [milestones/M1-offline-reliability.md](milestones/M1-offline-reliability.md) |
| M2 | Detection quality (multi-class + threshold UI) | M | [milestones/M2-detection-quality.md](milestones/M2-detection-quality.md) |
| M3 | Live UX (HUD, haptics, recent reports, undo) | M | [milestones/M3-live-ux.md](milestones/M3-live-ux.md) |
| M4 | Performance (battery/thermal, adaptive FPS, landscape) | M | [milestones/M4-performance.md](milestones/M4-performance.md) |
| M5 | Robust manual uploads & review step | M | [milestones/M5-manual-uploads.md](milestones/M5-manual-uploads.md) |
| M6 | Persistence & sync polish | S | [milestones/M6-sync-polish.md](milestones/M6-sync-polish.md) |

### Sequencing rationale

M1 first — every later milestone (M3 undo, M5 progress, M6 sweeper) depends on the SwiftData queue and background-session abstraction. M2 ships independently (no queue dependency, just `CameraManager` + Settings). M3 and M4 layer onto the live pipeline. M5 reuses M1 + M3 infrastructure. M6 is polish — releasable, but not blocking.

## Cross-cutting verification

After each milestone:

- **Unit (Swift Testing)**: `RetryPolicy`, `LabelCatalog`, `DetectionPreferences`, `ImageCompressor`, `DetectionGeometry` orientation transforms, `PendingReport` state machine.
- **UI (XCTest)**: live-start → cancel-snackbar → no-Firestore-write; manual-upload-no-GPS → manual-pin → success.
- **Manual on-device**: airplane-mode queue test, thermal-stress test, 4-orientation overlay alignment, force-quit-during-upload resume test.
- **Backend**: Firestore console check that `clientReportId` is unique per logical report (no dedupe failures); count of `detectionSource: "live_camera"` vs `"manual_image"` matches expected per session.

## Conventions for implementation PRs

- Branch naming: `claude/enhance-ios-detection-reports-<n>` for the umbrella branch; per-milestone branches `claude/ios-Mx-<slug>` cut from it.
- Commit prefixes mirror existing history: `feat:`, `refactor:`, `fix:`, `docs:`. Keep commits focused and imperative.
- Every milestone PR must update `docs/milestones/Mx-*.md` "Status" line at the top to track shipping (`planned` → `in-progress` → `shipped`).
- Build + simulator smoke before opening review:
  ```sh
  cd ios-app/HazardDetection
  python3 generate_project.py
  xcodebuild -project HazardDetection.xcodeproj -scheme HazardDetection \
    -destination 'platform=iOS Simulator,name=iPhone 15' build
  ```
- Schema changes must update both `Models.swift` and `PROJECT_SPEC.md` so the web and iOS clients stay aligned.

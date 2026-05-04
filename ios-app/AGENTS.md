# Repository Guidelines

## Project Structure & Module Organization

This directory contains the native iOS app in `HazardDetection/`. Source lives in `HazardDetection/HazardDetection/` and builds as one SwiftUI iOS target. Key files include `HazardDetectionApp.swift` for app entry, `ContentView.swift` and `MainTabView.swift` for top-level navigation, `CameraManager.swift` and `CameraView.swift` for camera integration, `LiveDetectionView.swift` for live detection, `UploadReportView.swift` for manual reports, and `BackendServices.swift` for the `ReportRepository`/`AppController`/`DetectionTracker` stack. Visual assets and ML resources sit beside the Swift files, including `best.mlpackage`, `best.mlmodelc`, and PNG mockups.

Project generation metadata is in `HazardDetection/project.yml`; `HazardDetection/generate_project.py` can regenerate the checked-in `.xcodeproj` if needed.

## Active Upgrade Roadmap

The live-detection and report-creation flows are mid-upgrade. Before changing those code paths, read `HazardDetection/docs/UPGRADE_ROADMAP.md` and the relevant milestone in `HazardDetection/docs/milestones/`. Honour the architectural decisions stated there:

- SwiftData (not CoreData) for any new on-device persistence.
- All new Cloudinary uploads route through `BackgroundUploadCoordinator` (M1) using a `URLSessionConfiguration.background` session.
- Every queued report carries a `clientReportId` UUID used as the Firestore idempotency key.
- Multi-class labels come from `MLModelDescription.classLabels` (or the bundled `labels.json` fallback) — do not extend the hardcoded switch in `CameraManager.swift`.
- Extend `DetectionTracker`, `ReportRepository`, `AppController`, `ImageAnnotator`, `DetectionGeometry` in place — do not introduce parallel state systems.

When a milestone ships, update the `Status:` line at the top of its design doc (`planned` → `in-progress` → `shipped`).

## Build, Test, and Development Commands

Run commands from the repository root unless noted.

```sh
cd HazardDetection
python3 generate_project.py
```

Regenerates `HazardDetection.xcodeproj`.
```sh
xcodebuild -project HazardDetection/HazardDetection.xcodeproj -scheme HazardDetection -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Builds the app for an iOS Simulator. Adjust the simulator name as needed.

```sh
xcodebuild -project HazardDetection/HazardDetection.xcodeproj -scheme HazardDetection -destination 'platform=iOS Simulator,name=iPhone 15' test
```

Runs tests once a test target exists. The current project does not include a test target.

## Coding Style & Naming Conventions

Use Swift 5.9 and iOS 17 APIs, matching `project.yml`. Follow standard Swift style: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties, methods, and local variables. Keep SwiftUI views small and declarative; move camera, model, and detection state into manager types instead of embedding side effects in view bodies.

Name SwiftUI views with a `View` suffix, for example `CameraView` or `LiveDetectionView`. Keep asset filenames descriptive and stable because they are referenced by the Xcode project.

## Testing Guidelines

Add tests under a future `HazardDetectionTests/` target using XCTest. Name test files after the unit under test, such as `CameraManagerTests.swift`, and use behavior-focused methods like `testStartsCaptureSessionWhenAuthorized()`. Prefer deterministic tests around parsing, state transitions, and model-output post-processing.

Before opening a PR, run a simulator build and any available XCTest suite.

## Commit & Pull Request Guidelines

Recent history mostly uses conventional prefixes such as `feat:` and `refactor:` with concise imperative summaries. Keep commits focused: `feat: add live detection overlay` or `refactor: extract camera permission handling`.

Pull requests should include a short description, testing performed, screenshots or recordings for UI changes, and notes for camera permissions, Core ML assets, or deployment settings. Link related issues when available.

## Security & Configuration Tips

Do not commit personal signing identities, populated development team IDs, or private provisioning assets. Keep camera permission copy in `Info.plist` accurate. Treat ML model files as versioned binary assets: replace them intentionally and verify simulator builds after updates.

## Schema Coordination With the Web Client

The iOS app and the web app share Firestore collections (`reports`, `users`, `metadata`) and a single Cloudinary upload preset. When you add a Firestore field on iOS, add it to the web client at the same time and update `/PROJECT_SPEC.md` so both sides stay in sync. The roadmap in `HazardDetection/docs/UPGRADE_ROADMAP.md` lists the additive fields planned for each milestone (`clientReportId`, `uploadAttempts`, `queuedAt`, `locationSource`, `rawLabel`).

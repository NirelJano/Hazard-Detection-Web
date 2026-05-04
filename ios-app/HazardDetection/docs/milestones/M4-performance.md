# M4 — Performance (Battery/Thermal, Adaptive FPS, Landscape)

**Status**: planned
**Complexity**: M
**Goal**: Sustained 30+ minute live sessions without throttling, full landscape support.

## Problem

The pipeline runs at fixed cadence (0.25s inference throttle, 60fps overlay render in `LiveDetectionView.swift:11,122-132`) regardless of thermal state or battery mode. On hot days or in dashboard-mounted use, the device throttles itself with no graceful degradation. The camera is hardcoded to portrait orientation in `CameraManager.storeLatestFrame` (`CameraManager.swift:204-211`) despite `Info.plist` allowing all orientations — landscape windshield-mount usage is broken (overlay misaligns).

## Scope

### Thermal & power adaptation

- `ProcessInfo.thermalStateDidChangeNotification` listener in `CameraManager`.
  - `.serious`: raise `inferenceInterval` from 0.25s → 0.5s.
  - `.critical`: pause inference, keep preview only; show HUD warning banner.
- `ProcessInfo.isLowPowerModeEnabled`: same throttle ladder.
- 60fps render timer in `LiveDetectionView.swift:11,122-132` reduced to 30fps under thermal pressure.

### Landscape support

- `CameraManager.setupSession` (`CameraManager.swift:104-130`) reads `UIDevice.orientation` and sets `videoOutput.connection(with:.video).videoRotationAngle`.
- Observe `UIDevice.orientationDidChangeNotification`; update both the data-output connection and `AVCaptureVideoPreviewLayer.connection.videoRotationAngle` in `CameraView.swift:37-60`.
- `storeLatestFrame` (`CameraManager.swift:204-211`) drops the hardcoded `.right` orientation; uses live device orientation.
- `DetectionGeometry.visionRectToImageRect` (`BackendServices.swift:712-759`) extended with an `orientation:` parameter so the bbox transform stays correct in portrait, landscapeLeft, landscapeRight, and portraitUpsideDown.
- Session reconfig wrapped in `beginConfiguration/commitConfiguration` to avoid frame loss.

## Files

**Modified**
- `CameraManager.swift` — thermal listener, orientation handling, dynamic interval.
- `CameraView.swift` — preview layer rotation, overlay coordinate transforms.
- `LiveDetectionView.swift` — render-timer throttle, HUD thermal banner.
- `BackendServices.swift` — `DetectionGeometry` orientation parameter.

**Created**
- `Performance/ThermalThrottler.swift` — observes notifications, publishes a `ThermalLevel` enum, drives interval changes.

## API surface

```swift
final class ThermalThrottler: ObservableObject {
    @Published private(set) var level: ThermalLevel = .nominal
    var inferenceInterval: TimeInterval { … }   // 0.25 / 0.5 / paused
    var renderFPS: Int { … }                    // 60 / 30 / 30
}

enum ThermalLevel { case nominal, fair, serious, critical }
```

`CameraManager` subscribes via Combine; `LiveDetectionView` reads the same publisher for the HUD banner and render timer.

## Reused

- Existing AVCaptureSession config (`CameraManager.swift:71-130`).
- Frame buffer, NSLock-guarded throttle (`80,144-150`).
- Preview layer setup (`CameraView.swift:37-60`).

## Risks & mitigations

- **Bbox coordinate transform regressions**: highest-risk change. Snapshot tests (XCTest with reference images) for each of 4 orientations + portraitUpsideDown.
- **Rotation mid-session frame drop**: batch reconfig with `beginConfiguration/commitConfiguration`. Hide preview during reconfig if visible frame jumps occur.
- **Throttle thrash**: debounce thermal-state changes (1s) to avoid oscillating between intervals.
- **Vision request orientation**: `VNImageRequestHandler(cvPixelBuffer:orientation:options:)` must receive the corrected `CGImagePropertyOrientation`; coordinate the data-output rotation with the Vision orientation parameter.

## Verification

- **Unit**: `DetectionGeometry` orientation tests with known input rects across all 4 orientations.
- **Manual on-device**:
  - Thermal: 30 min in direct sun with logging overlay (`ProcessInfo.thermalState` → log file). Confirm interval transitions and no app-store-rejection-triggering CPU spikes.
  - Landscape: rotate device through portrait → landscapeLeft → portraitUpsideDown → landscapeRight; confirm overlay aligns to ground-truth bounding boxes (test with a printed pothole reference).
  - Low Power Mode: enable in Settings; confirm interval matches `.serious` profile.
- **Snapshot tests**: bbox overlay images for each orientation against committed references.

## Open questions

- Should we surface the thermal level in Settings or only in the live HUD? Recommendation: HUD-only for non-power-users; Settings shows a small indicator.
- Pause inference at `.critical` or just throttle further? Recommendation: pause + banner — running inference at `.critical` risks a forced shutdown.
- Do we want a "performance mode" Settings toggle to lock to 0.5s interval permanently for older devices? Defer to user feedback.

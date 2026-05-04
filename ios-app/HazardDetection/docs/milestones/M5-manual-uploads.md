# M5 — Robust Manual Uploads & Review Step

**Status**: planned
**Complexity**: M
**Depends on**: M1 (queue), M3 (`EditPendingReportSheet`)
**Goal**: Manual uploads match live-flow reliability and offer fallbacks when GPS or EXIF is missing.

## Problem

`UploadReportView.saveReport` (`UploadReportView.swift:190-196`) bypasses any queue and uploads in-process — same failure mode as live (M1). Image quality is fixed at 0.8 (`CloudinaryService.swift:45`), so a 12MP photo can take 30s on flaky networks with no progress indicator. If GPS is unavailable AND EXIF is missing, `UploadReportView.swift:149-153` hard-errors and discards the photo. Users cannot manually pin a location, override the detected hazard type, or pull from the live camera buffer.

## Scope

- Rewrite `UploadReportView.saveReport` (`190-196`) to enqueue via SwiftData (the `PendingReport` path from M1). Manual path inherits offline + retry + progress for free.
- Adaptive JPEG compression (replaces fixed 0.8 in `CloudinaryService.swift:45`):
  - Target ≤ 1MB.
  - Quality range 0.5–0.9 (binary search until under target).
  - Downscale beyond max edge of 1920px.
  - Runs on a `Task.detached` to avoid blocking the main actor.
- Per-task progress via `URLSessionTaskDelegate.urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` → published `Progress` keyed by `PendingReport.id`; bind to a `ProgressView` in the upload card.
- Remove hard-error on missing GPS at `UploadReportView.swift:149-153`. Replace with manual-location flow:
  - Manual pin via MapKit `Map` with draggable annotation.
  - Manual hazard-type picker (driven by M2 `LabelCatalog`).
  - Photo source picker: camera | photo library | last-live-frame from `CameraManager.snapshotImage`.
- Editable review screen before submit reuses `EditPendingReportSheet` from M3 (photo + bbox preview, hazard-type picker, draggable location pin, read-only confidence). Submit enqueues.

## Files

**Modified**
- `UploadReportView.swift` — full flow rewrite around `EditPendingReportSheet` + queue.
- `CloudinaryService.swift` — adaptive compression, progress delegate hook.
- `BackendServices.swift` — `AppController.createUploadedReport` enqueues via M1 path.

**Created**
- `Upload/ManualLocationPickerView.swift` — MapKit + draggable pin.
- `Upload/ImageCompressor.swift` — binary-search JPEG quality + downscale, off-main.
- `Upload/UploadProgressView.swift` — per-row `ProgressView` bound to `BackgroundUploadCoordinator` publishers.

## Schema changes

**Firestore (`reports`)** — additive:

| Field | Type | Notes |
| --- | --- | --- |
| `locationSource` | string | `"exif"`, `"device"`, `"manual"` |
| `originalImageBytes` | int? | pre-compression size, telemetry only |
| `compressedImageBytes` | int? | post-compression size |

## Reused

- `GeocodingService.reverseGeocode` (`GeocodingService.swift:14`) — re-run when manual pin moves.
- `ImageAnnotator` (`BackendServices.swift:666-710`) — annotate preview in `EditPendingReportSheet`.
- M3 `EditPendingReportSheet` — same component, different entry point.
- M1 `PendingReport` queue + `BackgroundUploadCoordinator`.
- M2 `LabelCatalog` — drives the hazard-type picker options.

## Adaptive compression algorithm

```
target = 1_048_576 bytes
maxEdge = 1920
1. If image.size.maxEdge > maxEdge → downscale preserving aspect ratio.
2. quality = 0.85; data = jpegData(quality)
3. while data.count > target && quality > 0.5:
       quality -= 0.1; data = jpegData(quality)
4. if data.count > target: downscale by 0.8 and goto step 2 (max 2 iterations).
5. return data, quality, finalSize.
```

Run inside `Task.detached(priority: .utility)`; the main actor only awaits the result.

## Risks & mitigations

- **Large images on older devices**: profile on iPhone 11 baseline; cap max iteration to bound time spent.
- **EXIF GPS edge cases**: existing extractor (`UploadReportView.swift:342-359`) handles common formats; manual pin is the fallback when extraction fails.
- **MapKit memory**: `ManualLocationPickerView` uses `MapCameraPosition` and dismisses cleanly; do not retain across sheets.
- **Schema additive**: web client must tolerate missing `locationSource` on legacy rows.

## Verification

- **Unit**: `ImageCompressorTests` (target size, max iterations, downscale fallback).
- **UI (XCTest)**: upload-no-GPS flow → manual pin → success; upload progress reaches 100% before snackbar dismisses.
- **Manual on-device**: 12MP photo upload over slow 3G simulation in Xcode Network Link Conditioner — confirm < 1MB final size and visible progress.
- **Backend**: Firestore `locationSource` distribution after a test run; expect a mix of `exif` and `device` from real photos plus `manual` from synthetic tests.

## Open questions

- Should the live "snapshot last frame" feed into manual upload as a primary entry point (e.g., a button on the live HUD)? Recommendation: yes, ship as part of M5.
- Do we keep EXIF extraction for camera-captured images, or always trust device GPS? Recommendation: prefer EXIF when available (it's the moment-of-capture); fall back to device GPS at compose time.

# iOS Hazard Detection — Roadmap V2: Detection Sessions, Adaptive ROI, and Post-Processing

**Status**: planned
**Type**: planning-only PR
**Goal**: Upgrade the existing iOS live-detection and report-creation roadmap so the app behaves like a production field tool, not just a live detector that immediately writes every accepted detection as a report.

## Why this V2 exists

The first roadmap correctly prioritised offline reliability, background uploads, multi-class detection, live UX, performance, manual upload improvements, and sync polish.

This V2 adds the missing product layer between detection and reporting:

- one shared report creation pipeline for live detection and manual upload;
- a session-based detection model for each drive or capture run;
- adaptive ROI and confidence based on real camera conditions;
- CoreMotion, GPS speed, and camera-quality signals;
- lightweight real-time candidate collection;
- post-session cleanup that merges, filters, and finalises reports after recording ends.

The important change is conceptual:

```text
Raw frame detections → tracked candidates → session candidates → cleaned final reports → queued uploads
```

The app should not treat every live detection as a final report immediately.

## Updated sequencing

| ID | Title | Complexity | Why now |
| --- | --- | --- | --- |
| M0 | Unified report pipeline | M | Must happen before queueing so manual and live reports do not fork into separate systems. |
| M1 | Offline reliability foundation | L | Keeps reports safe once the unified pipeline creates them. |
| M2 | Detection quality and label handling | M | Removes hardcoded labels and adds baseline threshold controls. |
| M2.5 | Adaptive ROI, sensor fusion, and dynamic confidence | L | Reduces false positives from dashboards, bad angles, blur, speed, and lighting. |
| M3 | Live UX and review controls | M | Gives the user trust and limited control without distracting them while driving. |
| M3.5 | Detection session post-processing | L | Converts noisy candidates into clean final reports after the session ends. |
| M4 | Performance, thermal, landscape | M | Optimises live inference under real field conditions. |
| M5 | Manual upload review and fallback flow | M | Improves non-live reports using the same shared pipeline. |
| M6 | Sync polish and reconciliation | S | Cleans up edge cases after the core architecture is stable. |

## Architectural rules

- Keep the current app structure. Extend existing seams before creating new systems.
- `LiveDetectionView` and `UploadReportView` must both create `ReportDraft` objects and submit through the same service.
- Live detection creates candidates first, not final reports.
- Final Firestore reports are created only after validation, user review, or post-session finalisation.
- Use SwiftData for local persistence.
- Every final report must keep a stable `clientReportId` for idempotency.
- Keep raw detection metadata separate from user-facing report fields.
- Do not block live inference with heavy cleanup. Heavy checks run after the session or in background-safe chunks.

## M0 — Unified Report Pipeline

**Status**: in-progress
**Complexity**: M
**Goal**: Manual upload and live detection use one report creation path.

**Implementation note**: This milestone introduces `ReportDraft`, `ReportCreationService`, `ReportValidationPolicy`, `ReportPayloadBuilder`, and `ReportImagePreparer` under `HazardDetection/Reporting/`. Manual upload (`AppController.createUploadedReport`) and live detection (`AppController.submitLiveReport`) now both create a `ReportDraft` and submit through the same `ReportCreationService`. `createManualReport` is also routed through the service. Pre-resolved address is preserved on the draft and used by the service instead of re-geocoding. `createdAt` from the draft is respected via `createdAtMillis`. Validation requires location, image, and valid confidence. Image preparer fails fast on corrupt data. Existing Cloudinary upload and Firestore write behavior is unchanged. Build and smoke checks pending on macOS.

### Problem

Manual upload and live detection currently risk becoming two separate flows. That makes every future feature twice as hard: validation, Cloudinary upload, Firestore payload creation, image annotation, location fallback, dedupe, and queueing.

### Scope

Create shared models and services:

- `ReportDraft`
- `ReportDraftSource`
- `ReportCreationService`
- `ReportValidationPolicy`
- `ReportImagePreparer`
- `ReportPayloadBuilder`

`LiveDetectionView` / `AppController` and `UploadReportView` should both produce a `ReportDraft` and pass it to `ReportCreationService`.

### Draft model

```swift
struct ReportDraft: Identifiable, Codable {
    let id: UUID
    let source: ReportDraftSource
    var hazardType: String
    var rawLabel: String?
    var confidence: Double?
    var location: CLLocationCoordinate2D?
    var locationSource: LocationSource
    var imageLocalURL: URL
    var boundingBox: CGRect?
    var createdAt: Date
    var metadata: DetectionMetadata?
}

enum ReportDraftSource: String, Codable {
    case manualUpload
    case liveDetectionCandidate
    case postProcessedSession
}
```

### Acceptance criteria

- Manual upload and live detection no longer build Firestore payloads independently.
- Shared validation rejects missing image, missing hazard type, invalid location, and impossible confidence values.
- Existing Firestore schema remains backward-compatible.
- No new upload path is introduced outside the shared service.

## M1 — Offline Reliability Foundation

Keep the existing M1 plan, but update the input boundary:

```text
ReportCreationService
  → validates ReportDraft
  → stores PendingReport
  → BackgroundUploadCoordinator uploads image
  → ReportRepository commits final report by clientReportId
```

### Required additions

- `PendingReport` stores the encoded `ReportDraft`, not only a final `HazardReport` payload.
- `clientReportId` is generated before queue insertion.
- M1 must not know whether the draft came from manual upload, live detection, or post-session cleanup.

## M2 — Detection Quality and Label Handling

Keep the existing M2 plan, with one important correction:

- Detection output should create `DetectionCandidate`, not report objects.
- `rawLabel` and `displayLabel` should both be available.
- User-facing `hazardType` should be mapped late, at draft/finalisation time.

### Additional acceptance criteria

- The app can log raw model labels without changing user-facing report labels.
- Label filtering happens before tracking.
- Report finalisation can preserve both `rawLabel` and `hazardType`.

## M2.5 — Adaptive ROI, Sensor Fusion, and Dynamic Confidence

**Status**: planned
**Complexity**: L
**Goal**: Reduce false positives and improve difficult-condition detection without overloading the device.

### Problem

The camera is mounted in different vehicles and angles. A fixed ROI is too fragile. At the same time, the bottom part of the frame can include dashboard, buttons, mirrors, motorcycle parts, or phone mount artifacts. Lighting, blur, speed, and device vibration all change detection quality.

### Scope

Create:

- `RegionOfInterestManager`
- `CameraConditionAnalyzer`
- `MotionSignalProvider`
- `AdaptiveThresholdPolicy`
- `FrameQualityScore`
- `DetectionGate`

### ROI strategy

Use layered ROI rules:

1. **Default safe ROI**: ignore a configurable bottom band, for example 15% to 30% of the image.
2. **User focus area**: let the user drag or tap a wide focus region, like a camera focus area, not a tiny box.
3. **Device-angle adjustment**: use CoreMotion attitude to adjust the effective ROI when the phone is tilted.
4. **Landscape support**: keep ROI rules orientation-aware.
5. **Debug overlay**: show the active ROI during testing and optionally in advanced settings.

### Sensor and camera signals

Use cheap signals during live detection:

- GPS speed;
- GPS horizontal accuracy;
- heading if available;
- CoreMotion attitude;
- acceleration/vibration proxy;
- frame brightness;
- blur/sharpness estimate;
- exposure/ISO metadata when available;
- recent detection stability.

### Dynamic confidence policy

Dynamic threshold should not be only a slider. It should combine:

```text
effectiveThreshold = userBaseThreshold
  + labelBias
  + speedBias
  + blurBias
  + brightnessBias
  + roiBias
  + stabilityBias
```

Rules:

- A one-frame detection outside ROI should rarely become a candidate.
- A lower-confidence detection that appears across several stable frames may become a candidate.
- Dashboard/lower-band detections require higher confidence or repeated stability.
- High speed should prefer stability over single-frame confidence.
- Bad blur should increase threshold unless repeated detections agree.

### Acceptance criteria

- User can set a broad focus/ignore region.
- App has a default bottom ignore zone that can be tuned.
- Dynamic threshold is visible in debug diagnostics.
- Detection candidates include the condition score used at decision time.
- No heavy image analysis runs every frame. Expensive checks are throttled.

## M3 — Live UX and Review Controls

Keep the existing M3 plan, but change the mental model:

- Snackbar should refer to a candidate or queued draft, not necessarily a committed report.
- Recent rail should show candidates and finalised reports differently.
- The HUD should show:
  - active ROI state;
  - current effective threshold;
  - queue depth;
  - session duration;
  - candidate count;
  - discarded count in debug mode.

## M3.5 — Detection Session Post-Processing

**Status**: planned
**Complexity**: L
**Depends on**: M0, M1, M2.5
**Goal**: After a live capture session ends, clean noisy detections and create fewer, better reports.

### Problem

Live detection is noisy. The app should not upload every candidate immediately. During driving, the app should stay light. After the session ends, it can spend more time merging detections, picking the best image, removing obvious false positives, and finalising reports.

### Scope

Create:

- `DetectionSession`
- `SessionDetectionCandidate`
- `DetectionSessionStore`
- `CandidateClusterer`
- `FalsePositiveFilter`
- `BestFrameSelector`
- `ReportFinalizer`
- `SessionSummaryView`

### Session model

```swift
@Model
final class DetectionSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var routeSummaryJSON: Data?
    var statusRaw: String
    var candidateCount: Int
    var finalReportCount: Int
}

@Model
final class SessionDetectionCandidate {
    @Attribute(.unique) var id: UUID
    var sessionId: UUID
    var rawLabel: String
    var displayLabel: String
    var confidence: Double
    var effectiveThreshold: Double
    var conditionScoreJSON: Data
    var boundingBoxJSON: Data
    var locationJSON: Data?
    var timestamp: Date
    var imageLocalURL: URL?
    var statusRaw: String
}
```

### Post-processing flow

```text
Live session starts
  → collect lightweight candidates
  → save selected frames only, not every frame
  → session ends
  → cluster candidates by label, location, time, and bbox similarity
  → remove weak/isolated false positives
  → pick best frame per cluster
  → create ReportDraft objects
  → send drafts to ReportCreationService
  → queued upload handles the rest
```

### Merge policy

Merge candidates when they are likely the same physical hazard:

- same or compatible label;
- close GPS distance;
- close timestamp window;
- similar bbox position or movement path;
- repeated across enough frames.

### False-positive policy

Reject or downgrade candidates when:

- detection appears only once;
- bbox is mostly outside active ROI;
- bbox sits in ignored dashboard zone;
- frame is too blurry and candidate is not repeated;
- location accuracy is poor and no later candidate confirms it;
- label is disabled or below per-label quality threshold.

### Best-frame policy

Pick the image with the best combination of:

- confidence;
- sharpness;
- brightness;
- bbox visibility;
- distance from ignored ROI;
- location accuracy;
- least motion blur.

### UX

At the end of a session, show a compact summary:

- candidates found;
- final reports created;
- skipped weak detections;
- reports waiting for upload;
- option to review before upload if user enabled manual review.

### Acceptance criteria

- Live session can end with fewer final reports than raw candidates.
- Duplicate reports from the same pothole/crack are merged.
- The app keeps enough metadata to explain why a candidate was accepted or rejected.
- Final reports still go through the same `ReportCreationService` and offline queue.
- Post-processing can run in chunks without freezing the UI.

## M4 — Performance, Thermal, and Orientation

Keep existing M4, but include the new runtime controls:

- adaptive inference FPS based on thermal state, speed, and frame quality;
- skip expensive blur/brightness checks when stable;
- pause or reduce post-processing under high thermal state;
- orientation-aware `DetectionGeometry` and ROI transform tests;
- memory limits for saved session frames.

## M5 — Manual Upload Review and Fallback Flow

Keep existing M5, with one important rule:

Manual upload must use `ReportDraft` and `ReportCreationService` from M0.

Additional scope:

- manual user override of hazard type;
- manual location pin when GPS is missing;
- editable bounding box if detection exists;
- optional local model pass on uploaded image;
- same adaptive compression pipeline as live reports.

## M6 — Sync Polish and Reconciliation

Keep existing M6, but reconcile all levels:

- `DetectionSession`
- `SessionDetectionCandidate`
- `ReportDraft`
- `PendingReport`
- final Firestore report

A Firestore listener should not only prune uploaded pending rows. It should also update local session summaries once final reports are confirmed.

## Updated Firestore fields

Additive fields for final reports:

| Field | Type | Purpose |
| --- | --- | --- |
| `clientReportId` | string | Idempotency key. |
| `sourceSessionId` | string? | Links final report to a local live session. |
| `sourceCandidateIds` | string[]? | Candidates merged into this report. |
| `rawLabel` | string? | Model label before display mapping. |
| `displayLabel` | string? | App display label. |
| `effectiveThreshold` | number? | Threshold used when candidate was accepted. |
| `conditionScore` | map? | Blur, brightness, speed, ROI, stability summary. |
| `locationSource` | string? | gps, manual_pin, inferred, unknown. |
| `postProcessed` | bool | True when created after session cleanup. |
| `uploadAttempts` | int | Queue telemetry. |
| `queuedAt` | int64 | Client queue timestamp. |

All fields are additive and should not break old web clients.

## Implementation PR order

Recommended future PRs:

1. `refactor: add shared iOS report draft pipeline`
2. `feat: add SwiftData pending report queue`
3. `feat: add adaptive detection ROI and threshold policy`
4. `feat: add detection session storage and post-processing`
5. `feat: improve live detection HUD and review controls`
6. `feat: optimise live detection performance and orientation handling`
7. `feat: improve manual upload review flow`
8. `fix: reconcile local sessions with Firestore reports`

## Definition of done for the planning update

This planning update is complete when future agents can answer these questions before coding:

- Am I creating a raw detection, a candidate, a draft, a pending report, or a final Firestore report?
- Does this change belong to live detection, manual upload, session cleanup, or queueing?
- Am I using the shared `ReportCreationService`?
- Does this detection need to be finalised now, or should it wait for session cleanup?
- Does this logic run every frame, every few frames, on session end, or in background sync?
- Does the web client need a schema update?

## Non-goals for this V2 PR

- No Swift code implementation.
- No Firestore rule changes.
- No model retraining.
- No UI redesign.
- No change to Cloudinary credentials or upload preset.

This PR only upgrades the implementation plan so the next coding PRs are safer and more focused.

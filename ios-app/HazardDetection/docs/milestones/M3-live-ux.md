# M3 — Live UX (HUD, Haptics, Recent Reports, Undo)

**Status**: planned
**Complexity**: M
**Depends on**: M1 (queue + background coordinator)
**Goal**: Live detection feels controllable and trustworthy.

## Problem

Live auto-reports submit silently — there's no haptic confirmation, no visible recent-submission history, and no way to undo or edit a report once the tracker fires. The HUD (`LiveDetectionView.swift:137-200`) shows only GPS and total hazard count; queue depth, threshold, and reachability are invisible. Throttle/dedupe events (`BackendServices.swift:444-447`, `449-463`) silently swallow detections with no user-facing reason.

## Scope

- HUD additions: per-class detection count, current confidence threshold, queue depth, reachability dot, throttle/dedupe reason chips.
- `UINotificationFeedbackGenerator` `.success` on every accepted `LiveReportTrigger` in `AppController.submitLiveReport` (`BackendServices.swift:345`).
- Recent-reports rail: last 5 live submissions with thumbnail + timestamp, anchored below HUD.
- **Editable-review snackbar (non-blocking)**: when `submitLiveReport` enqueues, show a 6s overlay with Review / Edit / Cancel.
  - **Cancel**: marks `PendingReport.status = .cancelled`. `BackgroundUploadCoordinator` checks status before each task starts and skips cancelled rows.
  - **Edit**: opens `EditPendingReportSheet` pre-populated from queued payload; saving updates SwiftData row in place before upload starts.
  - **No action**: queue proceeds normally.

## Files

**Modified**
- `LiveDetectionView.swift` — HUD additions, snackbar host, recent-reports rail.
- `BackendServices.swift` (`AppController.submitLiveReport`) — emit haptic, attach review-window metadata.
- `UIComponents.swift` — extract reusable snackbar primitive.

**Created**
- `Live/ReviewSnackbar.swift` — auto-dismissing overlay with timer.
- `Live/EditPendingReportSheet.swift` — modal form for editing queued payload (reused by M5 manual upload).
- `Live/HapticEngine.swift` — thin wrapper, respects accessibility "Reduce Motion".
- `Live/RecentReportsRail.swift` — horizontal thumbnail strip backed by SwiftData query.

## Schema changes

SwiftData `PendingReport`:

| Field | Type | Notes |
| --- | --- | --- |
| `editedFields` | Data? | encoded user overrides applied at commit time |
| `reviewWindowEndsAt` | Date? | when the snackbar timer expires; coordinator must wait until past this time before uploading |

The coordinator gate becomes: only start `.pending` rows where `reviewWindowEndsAt == nil || reviewWindowEndsAt < Date()`.

## Reused

- `recentlySavedLabels` throttle (`BackendServices.swift:444-447`) — unchanged.
- `ImageAnnotator.drawBoundingBoxes` (`BackendServices.swift:666-710`) — used by the Edit sheet preview.
- `DetectionGeometry` for cropping the bbox in the recent-reports thumbnails.

## UX pattern: non-blocking review

Why non-blocking: drivers cannot reasonably interact with a modal while moving. The snackbar shows for 6s, fires haptic on appearance, does not steal focus, and defaults to "submit". Power users who want to edit/cancel can do so within the window; everyone else sees minimal disruption.

```
Tracker fires LiveReportTrigger
  └─ submitLiveReport()
       ├─ insert PendingReport(.pending, reviewWindowEndsAt: now+6s)
       ├─ HapticEngine.success()
       └─ NotificationCenter.default.post(.reviewSnackbarRequested, payload)

LiveDetectionView listens → presents ReviewSnackbar
  ├─ Cancel → PendingReport.status = .cancelled
  ├─ Edit   → present EditPendingReportSheet
  └─ Timer  → no-op (coordinator picks up at reviewWindowEndsAt)

BackgroundUploadCoordinator (M1) honors reviewWindowEndsAt gate.
```

## Risks & mitigations

- **Race between snackbar dismissal and background coordinator**: coordinator gates on `.pending` AND `reviewWindowEndsAt` being past. Cancel writes status atomically inside SwiftData transaction.
- **Haptic spam during dense detection**: `recentlySavedLabels` 10s throttle already prevents this; haptic only fires when a report is actually enqueued.
- **Accessibility**: respect `UIAccessibility.isReduceMotionEnabled` for snackbar slide-in; provide VoiceOver label "New hazard report. Tap to review."

## Verification

- **Unit**: snackbar timer logic, coordinator gate against `reviewWindowEndsAt`.
- **UI (XCTest)**: tap Cancel within 6s → no Firestore document created; tap Edit → label change reflected in committed Firestore document.
- **Manual**: confirm haptic fires once per accepted trigger; recent-reports rail shows last 5; HUD reachability dot flips when toggling airplane mode.
- **Accessibility**: VoiceOver reads snackbar; Reduce Motion suppresses animation.

## Open questions

- Review window length (6s) — measure with on-device usability; consider making it a Settings preference (4s/6s/10s/off).
- Should "Cancel" require confirmation? Default no — simpler is better; the haptic + snackbar already gives feedback.

# M1 — Offline Reliability Foundation

**Status**: planned
**Complexity**: L
**Goal**: No report is ever lost; uploads survive backgrounding and network loss.

## Problem

Today, `AppController.submitLiveReport` (`BackendServices.swift:345`) and `UploadReportView.saveReport` (`UploadReportView.swift:190-196`) both `await` Cloudinary + Firestore in-process. Any failure (airplane mode, app suspension mid-upload, transient 5xx) silently drops the report. The app has no notion of a queue, no retry, and no idempotency key — so even the user retrying manually risks duplicate Firestore documents.

## Scope

- SwiftData `PendingReport` queue model with state machine.
- `BackgroundUploadCoordinator` wrapping `URLSessionConfiguration.background`.
- `ReachabilityMonitor` (`NWPathMonitor`) gating dequeue on connectivity.
- `RetryPolicy` with exponential backoff (1s, 4s, 16s, 60s; cap 6 attempts).
- Refactor `CloudinaryService.uploadImage` (`CloudinaryService.swift:40-90`) to expose `prepareRequest(image:) -> (URLRequest, fileURL)` callable from a background session.
- Extract Firestore commit out of `ReportRepository.addReport` (`BackendServices.swift:75-218`) into `commitReport(payload:imageUrl:)` so the background callback can finalize.
- App-relaunch handler in `HazardDetectionApp.swift` to reattach the session by identifier (`application(_:handleEventsForBackgroundURLSession:completionHandler:)`).

## Files

**Modified**
- `BackendServices.swift` (`ReportRepository`, `AppController`)
- `CloudinaryService.swift`
- `HazardDetectionApp.swift`
- `SettingsView.swift` (pending-uploads list section)

**Created**
- `Persistence/HazardModelContainer.swift` — `ModelContainer` setup, `@MainActor` accessor.
- `Persistence/PendingReport.swift` — `@Model` entity.
- `Networking/BackgroundUploadCoordinator.swift` — `URLSessionDelegate` orchestrator.
- `Networking/ReachabilityMonitor.swift` — `NWPathMonitor` wrapper.
- `Networking/RetryPolicy.swift` — backoff schedule + jitter.

## SwiftData model

```swift
@Model
final class PendingReport {
    @Attribute(.unique) var id: UUID
    var clientReportId: String          // Firestore dedupe key (UUID string)
    var payloadJSON: Data               // encoded HazardReport-without-imageUrl
    var localImageURL: URL              // file:// path inside app sandbox
    var statusRaw: String               // PendingReportStatus
    var attempts: Int
    var lastError: String?
    var queuedAt: Date
    var lastAttemptAt: Date?
}

enum PendingReportStatus: String {
    case pending, uploading, uploaded, failed, cancelled
}
```

## Schema changes

**Firestore (`reports`)** — additive:

| Field | Type | Notes |
| --- | --- | --- |
| `clientReportId` | string | UUID, unique idempotency key |
| `uploadAttempts` | int | telemetry only |
| `queuedAt` | int64 (ms epoch) | client-side queue time |

Update Firestore Security Rules to allow `clientReportId` and reject documents missing it on `create` (gate behind a feature flag for staged rollout).

## Reused

- `ReportRepository` Firestore listener (`BackendServices.swift:48-65`) — unchanged, but will be augmented in M6 to prune local rows.
- Transactional counter (`160-184`) — moves from `addReport` into `commitReport`.
- `ConfigurationDiagnostics` — extend with reachability + queue depth diagnostics.

## Control flow (target)

```
LiveDetectionView / UploadReportView
  └─ AppController.submitLiveReport / createUploadedReport
       ├─ HazardModelContainer.insert(PendingReport(.pending))
       └─ BackgroundUploadCoordinator.kick()

BackgroundUploadCoordinator (URLSessionDelegate)
  ├─ if !ReachabilityMonitor.isOnline → return
  ├─ for each .pending row in queuedAt order:
  │    ├─ mark .uploading
  │    └─ session.uploadTask(withRequest: cloudinaryRequest, fromFile: localImageURL).resume()
  ├─ urlSession(_:task:didCompleteWithError:)
  │    ├─ on success: parse secure_url
  │    │    └─ ReportRepository.commitReport(payload, imageUrl)
  │    │         ├─ on success → mark .uploaded, delete row + image file
  │    │         └─ on failure → RetryPolicy.next(attempts) || mark .failed
  │    └─ on error: same retry path
  └─ on cancellation (M3 hook): row .cancelled → skip + cleanup
```

## Risks & mitigations

- **iOS may kill the background session** — `clientReportId` makes retries safe; reattach via session identifier on relaunch.
- **Photo file lifecycle** — `PendingReport` owns the file; SwiftData delete cascade triggers a `FileManager.removeItem` cleanup hook.
- **Firestore Security Rules drift between web and iOS** — coordinate `clientReportId` rule update with the web team before enforcing.

## Verification

- **Unit**: `RetryPolicyTests` (backoff sequence, jitter bounds), `PendingReportStateTests` (legal transitions), `BackgroundUploadCoordinatorTests` (mock session).
- **Integration**: airplane-mode test — queue 5 reports, re-enable network, all 5 land in Firestore exactly once (assert by `clientReportId` uniqueness).
- **Resilience**: force-quit during upload, relaunch — pending row resumes; no duplicate doc.
- **Telemetry**: log queue depth + last error in `SettingsView` diagnostics.

## Open questions

- Do we need a maximum local-queue size to prevent disk bloat? Proposal: cap at 200 pending; oldest `.failed` rows pruned with notification.
- Should the background sweeper (M6) be included here for completeness, or kept separate? Current plan: keep separate to ship M1 faster.

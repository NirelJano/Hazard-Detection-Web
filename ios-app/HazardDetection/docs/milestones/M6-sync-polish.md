# M6 — Persistence & Sync Polish

**Status**: planned
**Complexity**: S
**Depends on**: M1
**Goal**: Two-way consistency between local queue and Firestore listener; background sweeper for stale failures.

## Problem

After M1 ships, the local queue and the Firestore listener (`BackendServices.swift:48-65`) are independent. If the app dies after a successful Cloudinary upload but before SwiftData updates the row to `.uploaded`, the row will linger as `.uploading` forever. There's no Settings UI to inspect the queue, manually retry, or delete. There's also no background sweeper — failed uploads only retry when the app is foregrounded.

## Scope

- `ReportRepository` Firestore listener cross-references incoming docs with local `PendingReport` rows by `clientReportId`. Synced rows pruned (and their image files deleted).
- "Pending uploads" inbox in `SettingsView`: list, retry-now, delete-from-queue, view-error actions.
- Periodic `BGAppRefreshTask` (identifier `com.hazard.queue.sweep`) registered in `HazardDetectionApp.swift`. Retries `.failed` rows under retry cap when the app is backgrounded.

## Files

**Modified**
- `BackendServices.swift` — listener reconciliation logic on top of the existing `fetchReports` snapshot handler (`48-65`).
- `SettingsView.swift` — pending-uploads inbox.
- `HazardDetectionApp.swift` — `BGTaskScheduler.register` + `submit` lifecycle hooks.
- `Info.plist` — add `BGTaskSchedulerPermittedIdentifiers` entry.

**Created**
- `Background/QueueSweeperTask.swift` — `BGAppRefreshTask` handler.

## Reconciliation rule

```
on Firestore snapshot → for each added/modified doc:
    if doc.clientReportId matches local PendingReport.clientReportId:
        delete local row (and its image file)
        (the row was successfully committed; cleanup just hadn't happened locally)

on app foreground:
    for each PendingReport.uploading older than 60s:
        reset to .pending (assume coordinator died mid-flight)
```

## Reused

- M1 `BackgroundUploadCoordinator` — sweeper just calls `kick()`.
- M1 `RetryPolicy` — sweeper respects backoff schedule.
- Existing Firestore listener (`BackendServices.swift:48-65`).

## Risks & mitigations

- **BGTask quotas**: iOS heavily rate-limits `BGAppRefreshTask`. The sweeper must complete in < 30s and cap retries per invocation. Set earliestBeginDate to 15min from now.
- **Idempotent retries**: M1's `clientReportId` already prevents double-writes; sweeper inherits this.
- **Stuck `.uploading` rows**: timeout-based reset on foreground covers app crashes; coordinator should also `defer` a status revert on uncaught errors.

## Verification

- **Unit**: reconciliation logic unit test with synthetic Firestore snapshots and matching/non-matching local rows.
- **Manual on-device**: queue 3 reports → enable airplane mode → background app → re-enable network → leave overnight → morning open: queue empty, all 3 in Firestore.
- **Telemetry**: `SettingsView` shows queue depth, last sweep time, retry counts.
- **BGTask debugging**: use Xcode's "Simulate Background Refresh" to validate before relying on real iOS scheduling.

## Open questions

- Should the inbox be exposed only in admin builds or to all users? Recommendation: all users — it builds trust to see the queue is working.
- Manual "retry all" button or per-row only? Recommendation: both, with confirmation on the bulk action.

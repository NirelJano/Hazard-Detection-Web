# M2 — Detection Quality (Multi-Class + Threshold UI)

**Status**: planned
**Complexity**: M
**Goal**: Surface all relevant model classes with user-tunable confidence.

## Problem

The Core ML model `best.mlmodelc` exposes 80 class labels but `CameraManager.swift:56-62` only normalizes `"crack" → "Crack"` and `"pothole" → "Pothole"`; everything else falls through unhandled. Confidence thresholds are hardcoded (0.30/0.40 at `CameraManager.swift:149-153`, plus a tracker filter at `BackendServices.swift:523`). Users cannot tune sensitivity without a rebuild, and the tracker's IoU/age parameters (`BackendServices.swift:509-511`) are likewise locked.

## Scope

- `HazardDetector` reads `model.modelDescription.classLabels` once at init; expose `displayName(forRawLabel:)`.
- `LabelCatalog` curated subset of road-hazard classes (most YOLOv8 outputs are COCO categories irrelevant here) with per-label enable toggles persisted via `@AppStorage`.
- Settings slider for confidence threshold (range 0.20–0.80, default 0.40). Speed-adaptive bias remains an additive offset applied on top of the user value.
- Admin-only tracker tuning pane: `iouThreshold`, `maxAge`, `minHits` from `BackendServices.swift:509-511`.

## Files

**Modified**
- `CameraManager.swift` — replace label switch (`56-62`); read threshold from `DetectionPreferences`.
- `BackendServices.swift` (`DetectionTracker`) — read `iouThreshold/maxAge/minHits` from prefs.
- `SettingsView.swift` — add detection settings section.
- `Models.swift` — extend `HazardReport` only if we need `rawLabel` (decision in open questions).

**Created**
- `Detection/LabelCatalog.swift` — bundled `labels.json` parser, curated allowlist defaults.
- `Detection/DetectionPreferences.swift` — `ObservableObject` backed by `@AppStorage`.

**Resources**
- `Resources/labels.json` — fallback label list (only loaded if `model.modelDescription.classLabels` is empty).

## Defaults

```swift
struct DetectionPreferenceDefaults {
    static let confidenceThreshold: Double = 0.40
    static let speedAdaptiveBias: Double = -0.10  // applied above 13.8 m/s
    static let iouThreshold: Double = 0.30
    static let trackerMaxAge: Int = 15
    static let trackerMinHits: Int = 1
    static let enabledRoadHazardLabels: Set<String> = [
        "pothole", "crack", "speed_bump", "manhole",
        "debris", "road_damage", "patch", "rumble_strip"
    ]
}
```

`LabelCatalog` filters detector output to `enabledRoadHazardLabels` before emitting candidates to the tracker, so disabled labels never reach the report path.

## Reused

- `DetectionCandidate` struct unchanged.
- Tracker IoU math (`BackendServices.swift:540`).
- Existing speed source (`CameraManager.swift:144-150`).

## Risks & mitigations

- **COCO class noise**: default allowlist filters to road-hazard labels; users can opt-in to others via Settings.
- **Threshold mis-tuning**: bound the slider 0.20–0.80; store last-known-good in `DetectionPreferences` and offer "Reset to defaults".
- **Schema mismatch with web**: web client only knows the 2 normalized labels — coordinate with web team before adding new `hazardType` values to dashboards.

## Verification

- **Unit**: `LabelCatalogTests` (filter logic, default allowlist), `DetectionPreferencesTests` (persistence + bounds clamping).
- **Manual**: drive-test logs show class diversity beyond crack/pothole; threshold slider visibly changes overlay count and Firestore submission rate.
- **Backend**: query Firestore `reports` for distinct `hazardType` values after a test run; confirm new types appear and align with allowlist.

## Open questions

- Should we persist `rawLabel` separately from the human-readable `hazardType` for analytics? Recommended: yes, add `rawLabel: String?` to `HazardReport` and Firestore docs.
- Per-label confidence thresholds? Not in M2; revisit if drive-test data shows wide variance.

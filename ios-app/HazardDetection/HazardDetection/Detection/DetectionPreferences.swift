import Foundation

enum DetectionPreferenceDefaults {
    static let baseConfidenceThreshold: Double = 0.40
    static let highSpeedConfidenceOffset: Double = -0.10
    static let bottomIgnoreRatio: Double = 0.22
    static let enableAdaptiveThreshold: Bool = true
    static let enableROI: Bool = true
    static let enableMotionSignals: Bool = true
    static let enableFrameQualitySignals: Bool = true
    static let enableDebugOverlay: Bool = false
}

@MainActor
final class DetectionPreferences: ObservableObject {
    @Published var baseConfidenceThreshold: Double {
        didSet { defaults.set(baseConfidenceThreshold, forKey: Keys.baseConfidenceThreshold) }
    }
    @Published var highSpeedConfidenceOffset: Double {
        didSet { defaults.set(highSpeedConfidenceOffset, forKey: Keys.highSpeedConfidenceOffset) }
    }
    @Published var bottomIgnoreRatio: Double {
        didSet { defaults.set(bottomIgnoreRatio, forKey: Keys.bottomIgnoreRatio) }
    }
    @Published var enableAdaptiveThreshold: Bool {
        didSet { defaults.set(enableAdaptiveThreshold, forKey: Keys.enableAdaptiveThreshold) }
    }
    @Published var enableROI: Bool {
        didSet { defaults.set(enableROI, forKey: Keys.enableROI) }
    }
    @Published var enableMotionSignals: Bool {
        didSet { defaults.set(enableMotionSignals, forKey: Keys.enableMotionSignals) }
    }
    @Published var enableFrameQualitySignals: Bool {
        didSet { defaults.set(enableFrameQualitySignals, forKey: Keys.enableFrameQualitySignals) }
    }
    @Published var enableDebugOverlay: Bool {
        didSet { defaults.set(enableDebugOverlay, forKey: Keys.enableDebugOverlay) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        baseConfidenceThreshold = defaults.object(forKey: Keys.baseConfidenceThreshold) as? Double
            ?? DetectionPreferenceDefaults.baseConfidenceThreshold
        highSpeedConfidenceOffset = defaults.object(forKey: Keys.highSpeedConfidenceOffset) as? Double
            ?? DetectionPreferenceDefaults.highSpeedConfidenceOffset
        bottomIgnoreRatio = defaults.object(forKey: Keys.bottomIgnoreRatio) as? Double
            ?? DetectionPreferenceDefaults.bottomIgnoreRatio
        enableAdaptiveThreshold = defaults.object(forKey: Keys.enableAdaptiveThreshold) as? Bool
            ?? DetectionPreferenceDefaults.enableAdaptiveThreshold
        enableROI = defaults.object(forKey: Keys.enableROI) as? Bool
            ?? DetectionPreferenceDefaults.enableROI
        enableMotionSignals = defaults.object(forKey: Keys.enableMotionSignals) as? Bool
            ?? DetectionPreferenceDefaults.enableMotionSignals
        enableFrameQualitySignals = defaults.object(forKey: Keys.enableFrameQualitySignals) as? Bool
            ?? DetectionPreferenceDefaults.enableFrameQualitySignals
        enableDebugOverlay = defaults.object(forKey: Keys.enableDebugOverlay) as? Bool
            ?? DetectionPreferenceDefaults.enableDebugOverlay
    }

    func resetToDefaults() {
        baseConfidenceThreshold = DetectionPreferenceDefaults.baseConfidenceThreshold
        highSpeedConfidenceOffset = DetectionPreferenceDefaults.highSpeedConfidenceOffset
        bottomIgnoreRatio = DetectionPreferenceDefaults.bottomIgnoreRatio
        enableAdaptiveThreshold = DetectionPreferenceDefaults.enableAdaptiveThreshold
        enableROI = DetectionPreferenceDefaults.enableROI
        enableMotionSignals = DetectionPreferenceDefaults.enableMotionSignals
        enableFrameQualitySignals = DetectionPreferenceDefaults.enableFrameQualitySignals
        enableDebugOverlay = DetectionPreferenceDefaults.enableDebugOverlay
    }

    private enum Keys {
        static let baseConfidenceThreshold = "detection.baseConfidenceThreshold"
        static let highSpeedConfidenceOffset = "detection.highSpeedConfidenceOffset"
        static let bottomIgnoreRatio = "detection.bottomIgnoreRatio"
        static let enableAdaptiveThreshold = "detection.enableAdaptiveThreshold"
        static let enableROI = "detection.enableROI"
        static let enableMotionSignals = "detection.enableMotionSignals"
        static let enableFrameQualitySignals = "detection.enableFrameQualitySignals"
        static let enableDebugOverlay = "detection.enableDebugOverlay"
    }
}

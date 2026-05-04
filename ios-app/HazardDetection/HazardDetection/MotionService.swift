import CoreMotion
import Foundation

struct MotionSnapshot {
    let pitch: Double
    let roll: Double
    let yaw: Double
    let accelerationMagnitude: Double
    let rotationRate: Double
    let stabilityScore: Float
}

@MainActor
final class MotionService: ObservableObject {
    @Published private(set) var pitch: Double = 0
    @Published private(set) var roll: Double = 0
    @Published private(set) var yaw: Double = 0
    @Published private(set) var accelerationMagnitude: Double = 0
    @Published private(set) var rotationRate: Double = 0
    // 1.0 = perfectly stable, 0.0 = very unstable
    @Published private(set) var stabilityScore: Float = 1.0

    private let motionManager = CMMotionManager()
    private var recentAccelerations: [Double] = []
    private let windowSize = 10

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        // Deliver on main queue — process() is @MainActor and lightweight (pure arithmetic),
        // so running at 50 Hz on main is safe and avoids Task { @MainActor } hop issues.
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        recentAccelerations.removeAll()
    }

    func currentSnapshot() -> MotionSnapshot {
        MotionSnapshot(
            pitch: pitch,
            roll: roll,
            yaw: yaw,
            accelerationMagnitude: accelerationMagnitude,
            rotationRate: rotationRate,
            stabilityScore: stabilityScore
        )
    }

    private func process(_ motion: CMDeviceMotion) {
        pitch = motion.attitude.pitch
        roll = motion.attitude.roll
        yaw = motion.attitude.yaw

        let a = motion.userAcceleration
        let mag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        accelerationMagnitude = mag

        let r = motion.rotationRate
        rotationRate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()

        recentAccelerations.append(mag)
        if recentAccelerations.count > windowSize { recentAccelerations.removeFirst() }
        stabilityScore = Float(max(0, min(1, 1.0 - recentAccelerations.variance() * 10.0)))
    }
}

private extension [Double] {
    func variance() -> Double {
        guard count > 1 else { return 0 }
        let mean = reduce(0, +) / Double(count)
        return map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(count)
    }
}

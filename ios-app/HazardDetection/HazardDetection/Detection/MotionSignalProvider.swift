import CoreMotion
import Foundation

struct MotionSignal: Codable, Equatable {
    let pitch: Double?
    let roll: Double?
    let yaw: Double?
    let accelerationMagnitude: Double?
    let isDeviceStable: Bool
}

struct MotionSignalProvider {
    func signal(from snapshot: MotionSnapshot?) -> MotionSignal {
        guard let snapshot else {
            return MotionSignal(
                pitch: nil,
                roll: nil,
                yaw: nil,
                accelerationMagnitude: nil,
                isDeviceStable: true
            )
        }
        return MotionSignal(
            pitch: snapshot.pitch,
            roll: snapshot.roll,
            yaw: snapshot.yaw,
            accelerationMagnitude: snapshot.accelerationMagnitude,
            isDeviceStable: snapshot.stabilityScore >= 0.65
        )
    }
}

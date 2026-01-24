import Foundation
import CoreMotion
import Combine

class SensorService: ObservableObject {
    private let motionManager = CMMotionManager()

    @Published var heading: Double = 0.0 // Degrees True (if available)
    @Published var heel: Double = 0.0 // Degrees
    @Published var isReferenceFrameTrueNorth: Bool = false

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0

        // Prefer True North
        var refFrame: CMAttitudeReferenceFrame = .xMagneticNorthZVertical
        if CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) {
            refFrame = .xTrueNorthZVertical
            isReferenceFrameTrueNorth = true
        }

        motionManager.startDeviceMotionUpdates(using: refFrame, to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else { return }

            // Yaw is relative to the reference frame (True North if available)
            let azimuth = motion.attitude.yaw
            var degrees = -azimuth * (180.0 / .pi)
            if degrees < 0 { degrees += 360 }

            self.heading = degrees

            // Pitch as Heel (Landscape)
            let pitch = motion.attitude.pitch
            self.heel = pitch * (180.0 / .pi)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

import Foundation
import CoreMotion
import Combine

class SensorService: ObservableObject {
    private let motionManager = CMMotionManager()

    @Published var heading: Double = 0.0 // Degrees True (if available)
    @Published var heel: Double = 0.0 // Degrees
    @Published var isReferenceFrameTrueNorth: Bool = false

    func start() {
        #if targetEnvironment(simulator)
        startSimulatedUpdates()
        #else
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
        #endif
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        simTimer?.invalidate()
        simTimer = nil
    }

    // MARK: - Simulator-only synthetic sensor data
    // CoreMotion has no data source in the simulator, so synthesize a plausible
    // upwind beat: wind from 085°T, close-hauled at ~45° off the breeze,
    // tacking every 45 s, with helm scatter and wave-induced heel oscillation.

    private var simTimer: Timer?
    private var simElapsed: Double = 0
    private var simOnStarboard = true
    private var simHeading: Double = 40.0

    private func startSimulatedUpdates() {
        isReferenceFrameTrueNorth = true
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.simElapsed += 1.0 / 20.0
            let t = self.simElapsed

            if t.truncatingRemainder(dividingBy: 45.0) < 1.0 / 20.0 && t > 1 {
                self.simOnStarboard.toggle()
            }

            let target = self.simOnStarboard ? 40.0 : 130.0
            // Ease toward the target tack heading (~8 s turn), plus helm scatter
            var delta = target - self.simHeading
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            self.simHeading += delta * 0.015
            let scatter = 3.0 * sin(t * 0.7) + 1.5 * sin(t * 2.3)
            var heading = self.simHeading + scatter
            heading = heading.truncatingRemainder(dividingBy: 360)
            if heading < 0 { heading += 360 }
            self.heading = heading

            // Heel: leans the opposite way on each tack, with wave-period oscillation
            let baseHeel = self.simOnStarboard ? 15.0 : -15.0
            self.heel = baseHeel + 3.0 * sin(t * 1.8) + 1.0 * sin(t * 4.1)
        }
    }
}

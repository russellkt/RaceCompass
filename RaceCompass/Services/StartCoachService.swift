import Foundation
import CoreLocation
import Combine

// MARK: - Input/Output Structs

/// All inputs needed for the start coaching state machine
struct StartCoachInput {
    let secondsToStart: Double
    let currentLocation: CLLocation?
    let boatEnd: CLLocation?
    let pinEnd: CLLocation?
    let vmcToLine: Double
    let timeToLineVMC: Double
    let distanceToLine: Double
    let cog: Double
    let sog: Double
    let trueWindDirection: Double?
    let recordedUpwindSOG: Double
    let accelConfig: AccelerationConfig
}

/// All outputs from the start coaching state machine
struct StartCoachOutput {
    let startPhase: StartPhase
    let startStrategy: String
    let lineBias: Double
    let portApproachRecommended: Bool
    let suggestedReachCourse: Double
    let pastBoundary: Bool
    let targetReachDistance: Double
    let distanceAlongLine: Double

    static let setup = StartCoachOutput(
        startPhase: .setup,
        startStrategy: "SET LINE",
        lineBias: 0,
        portApproachRecommended: false,
        suggestedReachCourse: 0,
        pastBoundary: false,
        targetReachDistance: 0,
        distanceAlongLine: 0
    )
}

// MARK: - StartCoachService

/// Service responsible for the start line coaching state machine.
/// Encapsulates all decision logic for determining the current start phase
/// and providing tactical advice during the pre-start sequence.
class StartCoachService: ObservableObject {

    // MARK: - Published Outputs

    @Published private(set) var output: StartCoachOutput = .setup
    @Published private(set) var previousPhase: StartPhase = .setup

    // MARK: - Internal State

    /// Whether the target reach distance has been locked for the current maneuver
    private var isTargetLocked: Bool = false

    /// Position where the reach maneuver started
    private var reachStartPosition: CLLocation?

    /// Computed distance traveled along the line during reach maneuver
    private var distanceAlongLine: Double = 0

    /// Current locked target reach distance
    private var lockedTargetReachDistance: Double = 0

    // MARK: - Public Interface

    /// Update the coaching state with new input data.
    /// Call this method whenever input parameters change (typically on timer tick).
    /// - Parameter input: Current boat state and configuration
    /// - Returns: Whether a phase change occurred (for haptic feedback)
    @discardableResult
    func update(with input: StartCoachInput) -> Bool {
        let result = computePhase(input: input)
        let phaseChanged = result.startPhase != previousPhase

        previousPhase = output.startPhase
        output = result

        // Handle state cleanup on phase transitions
        if phaseChanged {
            handlePhaseTransition(from: previousPhase, to: result.startPhase)
        }

        return phaseChanged
    }

    /// Reset internal state (call when starting a new race)
    func reset() {
        isTargetLocked = false
        reachStartPosition = nil
        distanceAlongLine = 0
        lockedTargetReachDistance = 0
        previousPhase = .setup
        output = .setup
    }

    // MARK: - Private State Machine Logic

    private func computePhase(input: StartCoachInput) -> StartCoachOutput {
        // Guard: Need line endpoints to compute anything
        guard let boat = input.boatEnd, let pin = input.pinEnd else {
            return .setup
        }

        // Race started check
        if input.secondsToStart < -60 {
            return StartCoachOutput(
                startPhase: .raceStarted,
                startStrategy: "RACE STARTED",
                lineBias: output.lineBias,
                portApproachRecommended: output.portApproachRecommended,
                suggestedReachCourse: output.suggestedReachCourse,
                pastBoundary: false,
                targetReachDistance: 0,
                distanceAlongLine: 0
            )
        }

        // Calculate line bias if wind is set
        let (lineBias, portApproachRecommended) = calculateLineBias(
            boat: boat,
            pin: pin,
            trueWindDirection: input.trueWindDirection
        )

        // Calculate suggested reach course
        let suggestedReachCourse = calculateSuggestedReachCourse(
            boat: boat,
            pin: pin,
            currentLocation: input.currentLocation,
            portApproachRecommended: portApproachRecommended
        )

        // Check boundary conditions
        let pastBoundary = checkBoundary(
            boat: boat,
            pin: pin,
            currentLocation: input.currentLocation,
            suggestedReachCourse: suggestedReachCourse
        )

        // Calculate arrival metrics
        let timeToLine = input.vmcToLine > 0.1 ? input.timeToLineVMC : Double.infinity
        let isApproaching = input.vmcToLine > 0.1
        let arrivalMargin = input.secondsToStart - timeToLine

        // Update target reach distance (only if not locked)
        var targetReachDistance = lockedTargetReachDistance
        if !isTargetLocked {
            targetReachDistance = input.accelConfig.targetReachDistance(
                availableTime: input.secondsToStart,
                recordedUpwindSOG: input.recordedUpwindSOG
            )
        }

        // Calculate timing thresholds
        let maneuverTime = input.accelConfig.maneuverTime(forDistance: targetReachDistance)
        let reachStartTime = maneuverTime + 10
        let minApproachTime = input.accelConfig.timeToAccelerate + input.accelConfig.buffer + 20

        // Determine current phase and strategy
        let (phase, strategy) = determinePhaseAndStrategy(
            input: input,
            isApproaching: isApproaching,
            arrivalMargin: arrivalMargin,
            pastBoundary: pastBoundary,
            targetReachDistance: targetReachDistance,
            reachStartTime: reachStartTime,
            minApproachTime: minApproachTime,
            maneuverTime: maneuverTime,
            timeToLine: timeToLine,
            suggestedReachCourse: suggestedReachCourse,
            portApproachRecommended: portApproachRecommended
        )

        return StartCoachOutput(
            startPhase: phase,
            startStrategy: strategy,
            lineBias: lineBias,
            portApproachRecommended: portApproachRecommended,
            suggestedReachCourse: suggestedReachCourse,
            pastBoundary: pastBoundary,
            targetReachDistance: targetReachDistance,
            distanceAlongLine: distanceAlongLine
        )
    }

    private func calculateLineBias(
        boat: CLLocation,
        pin: CLLocation,
        trueWindDirection: Double?
    ) -> (Double, Bool) {
        guard let wind = trueWindDirection else {
            return (0, false)
        }

        let bearingPinToWind = (wind - RaceComputer.bearing(from: pin, to: boat) + 360)
            .truncatingRemainder(dividingBy: 360)
        let bearingBoatToWind = (wind - RaceComputer.bearing(from: boat, to: pin) + 360)
            .truncatingRemainder(dividingBy: 360)

        let pinAngleToWind = bearingPinToWind > 180 ? bearingPinToWind - 360 : bearingPinToWind
        let boatAngleToWind = bearingBoatToWind > 180 ? bearingBoatToWind - 360 : bearingBoatToWind

        let lineLength = pin.distance(from: boat)
        let angleDiff = abs(pinAngleToWind) - abs(boatAngleToWind)
        let lineBias = sin(angleDiff * .pi / 180) * lineLength
        let portApproachRecommended = lineBias > 10

        return (lineBias, portApproachRecommended)
    }

    private func calculateSuggestedReachCourse(
        boat: CLLocation,
        pin: CLLocation,
        currentLocation: CLLocation?,
        portApproachRecommended: Bool
    ) -> Double {
        let lineBearingPinToBoat = RaceComputer.bearing(from: pin, to: boat)
        let lineBearingBoatToPin = (lineBearingPinToBoat + 180).truncatingRemainder(dividingBy: 360)

        guard let loc = currentLocation else {
            return lineBearingPinToBoat
        }

        if portApproachRecommended {
            return lineBearingPinToBoat
        } else {
            let distToPin = loc.distance(from: pin)
            let distToBoat = loc.distance(from: boat)
            return distToPin < distToBoat ? lineBearingBoatToPin : lineBearingPinToBoat
        }
    }

    private func checkBoundary(
        boat: CLLocation,
        pin: CLLocation,
        currentLocation: CLLocation?,
        suggestedReachCourse: Double
    ) -> Bool {
        guard let loc = currentLocation else {
            return false
        }

        let lineBearingPinToBoat = RaceComputer.bearing(from: pin, to: boat)
        let lineBearingBoatToPin = (lineBearingPinToBoat + 180).truncatingRemainder(dividingBy: 360)

        let bearingFromPin = RaceComputer.bearing(from: pin, to: loc)
        let bearingFromBoat = RaceComputer.bearing(from: boat, to: loc)

        var angleFromPinEnd = abs(bearingFromPin - lineBearingPinToBoat)
        if angleFromPinEnd > 180 { angleFromPinEnd = 360 - angleFromPinEnd }

        var angleFromBoatEnd = abs(bearingFromBoat - lineBearingBoatToPin)
        if angleFromBoatEnd > 180 { angleFromBoatEnd = 360 - angleFromBoatEnd }

        let reachingTowardBoat = abs(suggestedReachCourse - lineBearingPinToBoat) < 90

        if reachingTowardBoat && angleFromPinEnd > 45 {
            return true
        } else if !reachingTowardBoat && angleFromBoatEnd > 45 {
            return true
        }

        return false
    }

    private func determinePhaseAndStrategy(
        input: StartCoachInput,
        isApproaching: Bool,
        arrivalMargin: Double,
        pastBoundary: Bool,
        targetReachDistance: Double,
        reachStartTime: Double,
        minApproachTime: Double,
        maneuverTime: Double,
        timeToLine: Double,
        suggestedReachCourse: Double,
        portApproachRecommended: Bool
    ) -> (StartPhase, String) {

        let accel = input.accelConfig

        // Late scenario
        if input.secondsToStart < 0 {
            if input.distanceToLine > 5 {
                return (.late, String(format: "LATE %.0fs", abs(input.secondsToStart)))
            } else {
                return (.go, "GO!")
            }
        }

        // Acceleration phase
        if input.secondsToStart <= accel.timeToAccelerate + accel.buffer {
            if isApproaching && timeToLine < input.secondsToStart + 2 {
                return (.go, String(format: "GO! %.0fs", input.secondsToStart))
            } else {
                return (.build, "BUILD SPEED")
            }
        }

        // Boundary check
        if pastBoundary {
            return (.turnBack, "BOUNDARY")
        }

        // Target reached during reach maneuver
        if distanceAlongLine >= targetReachDistance * 0.9 && isTargetLocked {
            let strategy = portApproachRecommended ? "TURN→PORT" : "TURN BACK"
            return (.turnBack, strategy)
        }

        // Reach maneuver phase
        if !isApproaching && input.secondsToStart <= reachStartTime && input.secondsToStart > minApproachTime {
            // Lock target and start position if transitioning into reach phase
            if previousPhase != .reachTo && previousPhase != .turnBack {
                lockedTargetReachDistance = input.accelConfig.targetReachDistance(
                    availableTime: input.secondsToStart,
                    recordedUpwindSOG: input.recordedUpwindSOG
                )
                reachStartPosition = input.currentLocation
                isTargetLocked = true
            }

            // Update distance traveled during reach
            if let startPos = reachStartPosition, let currentPos = input.currentLocation {
                distanceAlongLine = startPos.distance(from: currentPos)
            }

            let portIndicator = portApproachRecommended ? " P" : ""
            let strategy = String(format: "REACH %03.0f°%@", suggestedReachCourse, portIndicator)
            return (.reachTo, strategy)
        }

        // Build speed phase (late arrival)
        if isApproaching && arrivalMargin < 0 {
            return (.build, "BUILD SPEED")
        }

        // Hold phase (tight arrival margin)
        if isApproaching && arrivalMargin < accel.timeToAccelerate {
            return (.hold, String(format: "HOLD %.0fs", arrivalMargin))
        }

        // Slow down phase (too close, too fast)
        if isApproaching && arrivalMargin > 30 && input.distanceToLine < 50 {
            let targetSpeedKnots = max(
                1.0,
                input.distanceToLine / (input.secondsToStart - accel.timeToAccelerate) * Constants.metersPerSecondToKnots
            )
            return (.slowTo, String(format: "SLOW TO %.1fkt", targetSpeedKnots))
        }

        // Prep phase (far from start)
        if input.secondsToStart > 150 {
            return (.hold, "PREP")
        }

        // Default hold phases
        if isApproaching {
            return (.hold, String(format: "HOLD %.0fs", max(0, arrivalMargin)))
        } else {
            return (.hold, String(format: "HOLD %.0fs", max(0, input.secondsToStart - maneuverTime)))
        }
    }

    private func handlePhaseTransition(from previousPhase: StartPhase, to newPhase: StartPhase) {
        // Clean up reach maneuver state when leaving reach phases
        if previousPhase == .reachTo || previousPhase == .turnBack {
            if newPhase != .reachTo && newPhase != .turnBack {
                isTargetLocked = false
                reachStartPosition = nil
                distanceAlongLine = 0
                lockedTargetReachDistance = 0
            }
        }
    }
}

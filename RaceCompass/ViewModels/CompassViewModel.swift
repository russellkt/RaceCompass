import SwiftUI
import Combine
import CoreLocation

class CompassViewModel: ObservableObject {
    // Services
    private let locationService = LocationService()
    private let sensorService = SensorService()
    private let timerService = TimerService()
    private var cancellables = Set<AnyCancellable>()

    // --- RACE DATA ---
    @Published var displayHeading: Double = 0.0
    @Published var calibrationOffset: Double = 0.0
    @Published var isDragging: Bool = false
    @Published var sog: Double = 0.0
    @Published var cog: Double = 0.0
    @Published var heelAngle: Double = 0.0
    @Published var rawHeading: Double = 0.0

    // --- TRUE NORTH HANDLING ---
    @Published var headingIsTrueNorth: Bool = true
    @Published var headingWarning: String? = nil
    private var magneticDeclination: Double? = nil
    private var sensorIsTrueNorth: Bool = false

    // --- WIND & LAYLINE ---
    @Published var starboardTackRef: Double? = nil
    @Published var portTackRef: Double? = nil
    @Published var trueWindDirection: Double? = nil
    @Published var timeToLayline: Double = 0.0
    @Published var recordedUpwindSOG: Double = 5.0
    private var upwindSOGSamples: [Double] = []

    // --- START LINE DATA ---
    @Published var boatEnd: CLLocation?
    @Published var pinEnd: CLLocation?
    @Published var distanceToLine: Double = 0.0
    @Published var timeToBurn: Double = 0.0
    @Published var startStrategy: String = "SET TIME"

    // --- IMPROVED START COACHING ---
    @Published var vmcToLine: Double = 0.0
    @Published var timeToLineVMC: Double = 0.0
    @Published var bearingToLine: Double = 0.0
    @Published var startPhase: StartPhase = .setup
    @Published var targetReachDistance: Double = 0.0
    @Published var distanceAlongLine: Double = 0.0
    private var isTargetLocked: Bool = false
    private var reachStartPosition: CLLocation?
    @Published var suggestedReachCourse: Double = 0.0
    @Published var lineBias: Double = 0.0
    @Published var portApproachRecommended: Bool = false
    @Published var pastBoundary: Bool = false
    @Published var accelConfig = AccelerationConfig()

    // --- VMC & COURSE TRACKING ---
    @Published var courseMarks: [CLLocation] = []
    @Published var currentLeg: Int = 0
    @Published var nextMarkBearing: Double = 0.0
    @Published var vmcToMark: Double = 0.0
    @Published var distanceToMark: Double = 0.0

    // --- FIXED TIME TIMER ---
    @Published var targetTime: Date = Date()
    @Published var secondsToStart: TimeInterval = 0.0
    @Published var isTimerRunning = false

    var currentLocation: CLLocation?

    init() {
        setupSubscriptions()
        startServices()
    }

    func startServices() {
        locationService.start()
        sensorService.start()
        timerService.start()
    }

    func setupSubscriptions() {
        // Timer Loop
        timerService.$currentDate
            .sink { [weak self] _ in self?.updateTimerLogic() }
            .store(in: &cancellables)

        // Sensor Updates
        sensorService.$heading
            .sink { [weak self] newHeading in
                guard let self = self else { return }
                self.rawHeading = newHeading
                if !self.isDragging {
                    self.updateDisplay()
                }
            }
            .store(in: &cancellables)

        sensorService.$heel
            .assign(to: \.heelAngle, on: self)
            .store(in: &cancellables)

        sensorService.$isReferenceFrameTrueNorth
            .sink { [weak self] isTrueNorth in
                self?.sensorIsTrueNorth = isTrueNorth
                self?.updateHeadingReferenceState()
            }
            .store(in: &cancellables)

        // Location Updates
        locationService.$currentLocation
            .assign(to: \.currentLocation, on: self)
            .store(in: &cancellables)

        locationService.$sog
            .assign(to: \.sog, on: self)
            .store(in: &cancellables)

        locationService.$cog
            .assign(to: \.cog, on: self)
            .store(in: &cancellables)

        locationService.$magneticDeclination
            .sink { [weak self] declination in
                self?.magneticDeclination = declination
                self?.updateHeadingReferenceState()
            }
            .store(in: &cancellables)
    }

    /// Updates the heading reference state and warning based on True North availability
    private func updateHeadingReferenceState() {
        if sensorIsTrueNorth {
            // Best case: sensor provides True North directly
            headingIsTrueNorth = true
            headingWarning = nil
        } else if magneticDeclination != nil {
            // Good case: sensor is magnetic but we can convert using declination
            headingIsTrueNorth = true
            headingWarning = nil
        } else {
            // Warning case: magnetic heading without declination correction
            headingIsTrueNorth = false
            headingWarning = "Heading is Magnetic (no True North)"
        }
    }

    // --- LOGIC (Refactored to use RaceComputer) ---

    func updateTimerLogic() {
        let now = Date()
        let previousSeconds = self.secondsToStart
        self.secondsToStart = targetTime.timeIntervalSince(now)

        if previousSeconds >= 0 && secondsToStart < 0 {
             HapticManager.shared.playGun()
        }

        if secondsToStart > -60 {
            calculateLineStats()
            calculateLaylineStats()
        } else {
            startStrategy = "RACE STARTED"
        }

        if currentLeg == 0 && secondsToStart < 0 && !courseMarks.isEmpty {
            currentLeg = 1
        }

        calculateVMC()
        recordUpwindSOGIfCloseHauled()
    }

    func recordUpwindSOGIfCloseHauled() {
        guard sog > 0.5 else { return }
        guard let wind = trueWindDirection else { return }

        let currentHeading = displayHeading
        var isCloseHauled = false

        var angleToWind = abs(currentHeading - wind)
        if angleToWind > 180 { angleToWind = 360 - angleToWind }

        if angleToWind >= 30 && angleToWind <= 60 {
            isCloseHauled = true
        }

        if let stbdRef = starboardTackRef {
            var diffStbd = abs(currentHeading - stbdRef)
            if diffStbd > 180 { diffStbd = 360 - diffStbd }
            if diffStbd < 15 { isCloseHauled = true }
        }
        if let portRef = portTackRef {
            var diffPort = abs(currentHeading - portRef)
            if diffPort > 180 { diffPort = 360 - diffPort }
            if diffPort < 15 { isCloseHauled = true }
        }

        if isCloseHauled {
            upwindSOGSamples.append(sog)
            if upwindSOGSamples.count > 30 {
                upwindSOGSamples.removeFirst()
            }
            recordedUpwindSOG = upwindSOGSamples.reduce(0, +) / Double(upwindSOGSamples.count)
        }
    }

    // --- WIND LOGIC ---

    /// Returns the corrected heading (True North) for calculations
    private var correctedHeading: Double {
        var heading = rawHeading
        if !sensorIsTrueNorth, let declination = magneticDeclination {
            heading += declination
        }
        return heading
    }

    func setStarboardTack() { starboardTackRef = correctedHeading + calibrationOffset; calculateWindFromTacks() }
    func setPortTack() { portTackRef = correctedHeading + calibrationOffset; calculateWindFromTacks() }
    func setWindDirectly() {
        let current = (correctedHeading + calibrationOffset).truncatingRemainder(dividingBy: 360)
        trueWindDirection = current < 0 ? current + 360 : current
        starboardTackRef = nil; portTackRef = nil
    }

    func calculateWindFromTacks() {
        guard let s = starboardTackRef, let p = portTackRef else { return }
        var diff = abs(s - p)
        var wind: Double
        if diff < 180 { wind = (s + p) / 2 } else { wind = (s + p + 360) / 2 }
        wind = wind.truncatingRemainder(dividingBy: 360)
        if wind < 0 { wind += 360 }
        trueWindDirection = wind
    }

    // --- LAYLINE CALCULATOR ---
    func calculateLaylineStats() {
        guard let wind = trueWindDirection, let loc = currentLocation, let boat = boatEnd, let pin = pinEnd else { return }

        let distToPin = loc.distance(from: pin)
        let distToBoat = loc.distance(from: boat)
        let isAimingForPin = distToPin < distToBoat
        let targetMark = isAimingForPin ? pin : boat

        var tackAngle = 45.0
        if let s = starboardTackRef, let p = portTackRef {
            var diff = abs(s - p)
            if diff > 180 { diff = 360 - diff }
            tackAngle = max(30, min(60, diff / 2.0))
        }

        let laylineBearing = isAimingForPin ? (wind - tackAngle) : (wind + tackAngle)
        self.timeToLayline = RaceComputer.calculateIntersectionTime(boatPos: loc, boatHeading: cog, boatSpeed: sog, markPos: targetMark, laylineBearing: laylineBearing)
    }

    // --- START COMPUTER ---
    func calculateLineStats() {
        guard let userLoc = currentLocation, let boat = boatEnd, let pin = pinEnd else {
            startPhase = .setup
            startStrategy = "SET LINE"
            return
        }

        let distMeters = RaceComputer.distanceFromPointToLine(p: userLoc, a: pin, b: boat)
        self.distanceToLine = distMeters

        calculateVMCToLine()

        let targetSpeedKnots = sog < 1.0 ? accelConfig.targetSpeed : sog
        let speedMS = targetSpeedKnots * Constants.knotsToMetersPerSecond
        let timeToTravel = distMeters / speedMS
        self.timeToBurn = secondsToStart - timeToTravel

        determineStartPhase()
    }

    func calculateVMCToLine() {
        guard let userLoc = currentLocation, let boat = boatEnd, let pin = pinEnd else {
            vmcToLine = 0
            timeToLineVMC = 0
            bearingToLine = 0
            return
        }

        let closestPoint = RaceComputer.closestPointOnLine(p: userLoc, a: pin, b: boat)
        bearingToLine = RaceComputer.bearing(from: userLoc, to: closestPoint)

        let angleDiff = (cog - bearingToLine) * .pi / 180
        vmcToLine = sog * cos(angleDiff)

        let distMeters = distanceToLine
        if vmcToLine > 0.1 {
            let speedMS = vmcToLine * Constants.knotsToMetersPerSecond
            timeToLineVMC = distMeters / speedMS
        } else if vmcToLine < -0.1 {
            let speedMS = abs(vmcToLine) * Constants.knotsToMetersPerSecond
            timeToLineVMC = -(distMeters / speedMS)
        } else {
            timeToLineVMC = Double.infinity
        }
    }

    // This method is stateful and relies on many properties, so I'll keep it here but use RaceComputer for calculations
    func determineStartPhase() {
        let previousPhase = startPhase

        guard let boat = boatEnd, let pin = pinEnd else {
            startPhase = .setup
            startStrategy = "SET LINE"
            return
        }

        if secondsToStart < -60 {
            startPhase = .raceStarted
            startStrategy = "RACE STARTED"
            return
        }

        if let wind = trueWindDirection {
            let bearingPinToWind = (wind - RaceComputer.bearing(from: pin, to: boat) + 360).truncatingRemainder(dividingBy: 360)
            let bearingBoatToWind = (wind - RaceComputer.bearing(from: boat, to: pin) + 360).truncatingRemainder(dividingBy: 360)

            let pinAngleToWind = bearingPinToWind > 180 ? bearingPinToWind - 360 : bearingPinToWind
            let boatAngleToWind = bearingBoatToWind > 180 ? bearingBoatToWind - 360 : bearingBoatToWind

            let lineLength = pin.distance(from: boat)
            let angleDiff = abs(pinAngleToWind) - abs(boatAngleToWind)
            lineBias = sin(angleDiff * .pi / 180) * lineLength
            portApproachRecommended = lineBias > 10
        } else {
            lineBias = 0
            portApproachRecommended = false
        }

        let lineBearingPinToBoat = RaceComputer.bearing(from: pin, to: boat)
        let lineBearingBoatToPin = (lineBearingPinToBoat + 180).truncatingRemainder(dividingBy: 360)

        if let loc = currentLocation {
            let distToPin = loc.distance(from: pin)
            let distToBoat = loc.distance(from: boat)

            if portApproachRecommended {
                suggestedReachCourse = lineBearingPinToBoat
            } else {
                suggestedReachCourse = distToPin < distToBoat ? lineBearingBoatToPin : lineBearingPinToBoat
            }
        } else {
            suggestedReachCourse = lineBearingPinToBoat
        }

        pastBoundary = false
        if let loc = currentLocation {
            let bearingFromPin = RaceComputer.bearing(from: pin, to: loc)
            let bearingFromBoat = RaceComputer.bearing(from: boat, to: loc)

            var angleFromPinEnd = abs(bearingFromPin - lineBearingPinToBoat)
            if angleFromPinEnd > 180 { angleFromPinEnd = 360 - angleFromPinEnd }

            var angleFromBoatEnd = abs(bearingFromBoat - lineBearingBoatToPin)
            if angleFromBoatEnd > 180 { angleFromBoatEnd = 360 - angleFromBoatEnd }

            let reachingTowardBoat = abs(suggestedReachCourse - lineBearingPinToBoat) < 90
            if reachingTowardBoat && angleFromPinEnd > 45 {
                pastBoundary = true
            } else if !reachingTowardBoat && angleFromBoatEnd > 45 {
                pastBoundary = true
            }
        }

        let timeToLine = vmcToLine > 0.1 ? timeToLineVMC : Double.infinity
        let isApproaching = vmcToLine > 0.1

        let arrivalMargin = secondsToStart - timeToLine

        if !isTargetLocked {
            targetReachDistance = accelConfig.targetReachDistance(availableTime: secondsToStart, recordedUpwindSOG: recordedUpwindSOG)
        }

        let maneuverTime = accelConfig.maneuverTime(forDistance: targetReachDistance)
        let reachStartTime = maneuverTime + 10
        let minApproachTime = accelConfig.timeToAccelerate + accelConfig.buffer + 20

        if secondsToStart < 0 {
            if distanceToLine > 5 {
                startPhase = .late
                startStrategy = String(format: "LATE %.0fs", abs(secondsToStart))
            } else {
                startPhase = .go
                startStrategy = "GO!"
            }
        } else if secondsToStart <= accelConfig.timeToAccelerate + accelConfig.buffer {
            if isApproaching && timeToLine < secondsToStart + 2 {
                startPhase = .go
                startStrategy = String(format: "GO! %.0fs", secondsToStart)
            } else {
                startPhase = .build
                startStrategy = "BUILD SPEED"
            }
        } else if pastBoundary {
            startPhase = .turnBack
            startStrategy = "BOUNDARY"
        } else if distanceAlongLine >= targetReachDistance * 0.9 && isTargetLocked {
            startPhase = .turnBack
            startStrategy = portApproachRecommended ? "TURN→PORT" : "TURN BACK"
        } else if !isApproaching && secondsToStart <= reachStartTime && secondsToStart > minApproachTime {
            if previousPhase != .reachTo && previousPhase != .turnBack {
                targetReachDistance = accelConfig.targetReachDistance(availableTime: secondsToStart, recordedUpwindSOG: recordedUpwindSOG)
                reachStartPosition = currentLocation
                isTargetLocked = true
            }
            if let startPos = reachStartPosition, let currentPos = currentLocation {
                distanceAlongLine = startPos.distance(from: currentPos)
            }
            startPhase = .reachTo
            let portIndicator = portApproachRecommended ? " P" : ""
            startStrategy = String(format: "REACH %03.0f°%@", suggestedReachCourse, portIndicator)
        } else if isApproaching && arrivalMargin < 0 {
            startPhase = .build
            startStrategy = "BUILD SPEED"
        } else if isApproaching && arrivalMargin < accelConfig.timeToAccelerate {
            startPhase = .hold
            startStrategy = String(format: "HOLD %.0fs", arrivalMargin)
        } else if isApproaching && arrivalMargin > 30 && distanceToLine < 50 {
            let targetSpeedKnots = max(1.0, distanceToLine / (secondsToStart - accelConfig.timeToAccelerate) * Constants.metersPerSecondToKnots)
            startPhase = .slowTo
            startStrategy = String(format: "SLOW TO %.1fkt", targetSpeedKnots)
        } else if secondsToStart > 150 {
            startPhase = .hold
            startStrategy = "PREP"
        } else if isApproaching {
            startPhase = .hold
            startStrategy = String(format: "HOLD %.0fs", max(0, arrivalMargin))
        } else {
            startPhase = .hold
            startStrategy = String(format: "HOLD %.0fs", max(0, secondsToStart - maneuverTime))
        }

        if startPhase != previousPhase {
            HapticManager.shared.playPhaseChange()
            if previousPhase == .reachTo || previousPhase == .turnBack {
                if startPhase != .reachTo && startPhase != .turnBack {
                    isTargetLocked = false
                    reachStartPosition = nil
                    distanceAlongLine = 0
                }
            }
        }
    }

    func pingBoat() { boatEnd = currentLocation }
    func pingPin() { pinEnd = currentLocation }

    // --- VMC CALCULATIONS ---
    func calculateVMC() {
        guard let loc = currentLocation else { return }

        let target: CLLocation?
        if currentLeg == 0 {
            if let pin = pinEnd, let boat = boatEnd {
                let midLat = (pin.coordinate.latitude + boat.coordinate.latitude) / 2
                let midLon = (pin.coordinate.longitude + boat.coordinate.longitude) / 2
                target = CLLocation(latitude: midLat, longitude: midLon)
            } else {
                target = nil
            }
        } else {
            let markIndex = currentLeg - 1
            if markIndex < courseMarks.count {
                target = courseMarks[markIndex]
            } else {
                target = nil
            }
        }

        guard let targetMark = target else {
            nextMarkBearing = 0
            vmcToMark = 0
            distanceToMark = 0
            return
        }

        nextMarkBearing = RaceComputer.bearing(from: loc, to: targetMark)
        distanceToMark = loc.distance(from: targetMark)

        let angleDiff = (cog - nextMarkBearing) * .pi / 180
        vmcToMark = sog * cos(angleDiff)

        if currentLeg > 0 && distanceToMark < Constants.markRoundingDistance {
            advanceToNextLeg()
        }
    }

    func advanceToNextLeg() {
        if currentLeg < courseMarks.count {
            currentLeg += 1
        }
    }

    func resetToPreStart() {
        currentLeg = 0
    }

    func syncTimer(minutes: Double) {
        targetTime = Date().addingTimeInterval(minutes * 60)
        updateTimerLogic()
    }

    func updateDisplay() {
        // Apply magnetic declination correction if sensor is magnetic and we have declination
        var correctedHeading = rawHeading
        if !sensorIsTrueNorth, let declination = magneticDeclination {
            correctedHeading = rawHeading + declination
        }

        var target = (correctedHeading + calibrationOffset).truncatingRemainder(dividingBy: 360)
        if target < 0 { target += 360 }
        let diff = target - displayHeading
        let shortestDiff = (diff + 540).truncatingRemainder(dividingBy: 360) - 180
        if abs(shortestDiff) > 180 { displayHeading = target } else { displayHeading += shortestDiff * Constants.headingDampingFactor }
        displayHeading = displayHeading.truncatingRemainder(dividingBy: 360)
        if displayHeading < 0 { displayHeading += 360 }
    }

    func manualAdjust(newValue: Double) {
        var normalized = newValue.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        calibrationOffset = normalized
        updateDisplay()
    }
}

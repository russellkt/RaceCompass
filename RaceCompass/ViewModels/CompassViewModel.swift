import SwiftUI
import Combine
import CoreLocation

class CompassViewModel: ObservableObject {
    // Services
    private let locationService = LocationService()
    private let sensorService = SensorService()
    private let timerService = TimerService()
    private let startCoachService = StartCoachService()
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

    // --- RACE ELAPSED TIMER ---
    @Published var raceElapsedTime: TimeInterval = 0.0
    @Published var isRaceTimerRunning = true
    private var raceTimerPausedAt: TimeInterval? = nil

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

        // Update race elapsed timer after start
        if secondsToStart < 0 {
            if isRaceTimerRunning {
                raceElapsedTime = abs(secondsToStart)
            }
            // If paused, raceElapsedTime stays at the paused value
        } else {
            raceElapsedTime = 0
            raceTimerPausedAt = nil
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

    func toggleRaceTimer() {
        if isRaceTimerRunning {
            // Pause: store current elapsed time
            raceTimerPausedAt = raceElapsedTime
            isRaceTimerRunning = false
        } else {
            // Resume: adjust target time so elapsed continues from paused value
            if let pausedAt = raceTimerPausedAt {
                targetTime = Date().addingTimeInterval(-pausedAt)
            }
            isRaceTimerRunning = true
        }
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

    /// Delegates start phase determination to the StartCoachService.
    /// This keeps the ViewModel thin while the service encapsulates all coaching logic.
    func determineStartPhase() {
        let input = StartCoachInput(
            secondsToStart: secondsToStart,
            currentLocation: currentLocation,
            boatEnd: boatEnd,
            pinEnd: pinEnd,
            vmcToLine: vmcToLine,
            timeToLineVMC: timeToLineVMC,
            distanceToLine: distanceToLine,
            cog: cog,
            sog: sog,
            trueWindDirection: trueWindDirection,
            recordedUpwindSOG: recordedUpwindSOG,
            accelConfig: accelConfig
        )

        let phaseChanged = startCoachService.update(with: input)
        let output = startCoachService.output

        // Update published properties from service output
        startPhase = output.startPhase
        startStrategy = output.startStrategy
        lineBias = output.lineBias
        portApproachRecommended = output.portApproachRecommended
        suggestedReachCourse = output.suggestedReachCourse
        pastBoundary = output.pastBoundary
        targetReachDistance = output.targetReachDistance
        distanceAlongLine = output.distanceAlongLine

        // Trigger haptic feedback on phase change
        if phaseChanged {
            HapticManager.shared.playPhaseChange()
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

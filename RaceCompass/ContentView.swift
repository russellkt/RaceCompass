import SwiftUI
import CoreMotion
import CoreLocation
import Combine

// MARK: - 1. THE LOGIC (Date-Based Timer)
class CompassViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    
    // --- RACE DATA ---
    @Published var displayHeading: Double = 0.0
    @Published var calibrationOffset: Double = 0.0
    @Published var isDragging: Bool = false
    @Published var sog: Double = 0.0
    @Published var cog: Double = 0.0
    @Published var heelAngle: Double = 0.0
    @Published var rawHeading: Double = 0.0
    
    // --- WIND & LAYLINE ---
    @Published var starboardTackRef: Double? = nil
    @Published var portTackRef: Double? = nil
    @Published var trueWindDirection: Double? = nil
    @Published var timeToLayline: Double = 0.0
    
    // --- START LINE DATA ---
    @Published var boatEnd: CLLocation?
    @Published var pinEnd: CLLocation?
    @Published var distanceToLine: Double = 0.0
    @Published var timeToBurn: Double = 0.0
    @Published var startStrategy: String = "SET TIME"

    // --- IMPROVED START COACHING ---
    @Published var vmcToLine: Double = 0.0          // VMC toward closest point on line (knots)
    @Published var timeToLineVMC: Double = 0.0      // Time to line at current VMC (seconds)
    @Published var startPhase: StartPhase = .setup  // Current coaching phase
    @Published var targetReachDistance: Double = 0.0 // How far to reach out (meters)
    @Published var accelConfig = AccelerationConfig()

    // --- VMC & COURSE TRACKING ---
    @Published var courseMarks: [CLLocation] = []  // Ordered marks from course setup
    @Published var currentLeg: Int = 0             // 0 = pre-start, 1+ = racing legs
    @Published var nextMarkBearing: Double = 0.0   // Bearing to next mark
    @Published var vmcToMark: Double = 0.0         // VMC to target (knots)
    @Published var distanceToMark: Double = 0.0    // Distance to next mark (meters)
    
    // --- FIXED TIME TIMER ---
    @Published var targetTime: Date = Date() // The exact wall-clock time the race starts
    @Published var secondsToStart: TimeInterval = 0.0
    @Published var isTimerRunning = false
    private var timer: Timer?
    
    var currentLocation: CLLocation?
    
    override init() {
        super.init()
        startSensorFusion()
        startGPS()
        // Start the clock loop immediately so UI is always fresh
        startClockLoop()
    }
    
    // --- CLOCK LOOP ---
    // Instead of a countdown, we tick every 0.1s to update the math based on current time
    func startClockLoop() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            self.updateTimerLogic()
        }
    }
    
    func updateTimerLogic() {
        // 1. Calculate Time Remaining
        let now = Date()
        self.secondsToStart = targetTime.timeIntervalSince(now)

        // 2. Update Strategies
        if secondsToStart > -60 { // Keep calculating for 1 min after start
            calculateLineStats()
            calculateLaylineStats()
        } else {
            startStrategy = "RACE STARTED"
        }

        // 3. Auto-advance from pre-start to racing when timer goes negative
        if currentLeg == 0 && secondsToStart < 0 && !courseMarks.isEmpty {
            currentLeg = 1
        }

        // 4. Calculate VMC to target
        calculateVMC()
    }
    
    // --- SENSOR FUSION ---
    func startSensorFusion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        motionManager.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else { return }
            
            let azimuth = motion.attitude.yaw
            var degrees = -azimuth * (180.0 / .pi)
            if degrees < 0 { degrees += 360 }
            self.rawHeading = degrees
            
            let pitch = motion.attitude.pitch
            self.heelAngle = pitch * (180.0 / .pi)
            
            if !self.isDragging { self.updateDisplay() }
        }
    }
    
    // --- GPS ---
    func startGPS() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.currentLocation = location
        if location.speed >= 0 { self.sog = location.speed * 1.94384 }
        if location.course >= 0 { self.cog = location.course }
    }
    
    // --- WIND LOGIC ---
    func setStarboardTack() { starboardTackRef = rawHeading + calibrationOffset; calculateWindFromTacks() }
    func setPortTack() { portTackRef = rawHeading + calibrationOffset; calculateWindFromTacks() }
    func setWindDirectly() {
        let current = (rawHeading + calibrationOffset).truncatingRemainder(dividingBy: 360)
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
        self.timeToLayline = calculateIntersectionTime(boatPos: loc, boatHeading: cog, boatSpeed: sog, markPos: targetMark, laylineBearing: laylineBearing)
    }
    
    func calculateIntersectionTime(boatPos: CLLocation, boatHeading: Double, boatSpeed: Double, markPos: CLLocation, laylineBearing: Double) -> Double {
        let dLat = markPos.coordinate.latitude - boatPos.coordinate.latitude
        let dLon = markPos.coordinate.longitude - boatPos.coordinate.longitude
        let metersPerLat = 111139.0
        let metersPerLon = cos(boatPos.coordinate.latitude * .pi/180) * 111139.0
        let Qx = dLon * metersPerLon; let Qy = dLat * metersPerLat
        let d2r = Double.pi / 180.0
        let Vx = sin(boatHeading * d2r); let Vy = cos(boatHeading * d2r)
        let Wx = sin(laylineBearing * d2r); let Wy = cos(laylineBearing * d2r)
        let det = Vx * (-Wy) - Vy * (-Wx)
        if abs(det) < 0.001 { return 0 }
        let detT = Qx * (-Wy) - Qy * (-Wx)
        let t_meters = detT / det
        let speedMS = max(boatSpeed / 1.94384, 0.1)
        return t_meters / speedMS
    }
    
    // --- START COMPUTER (Using Date) ---
    func calculateLineStats() {
        guard let userLoc = currentLocation, let boat = boatEnd, let pin = pinEnd else {
            startPhase = .setup
            startStrategy = "SET LINE"
            return
        }

        // Calculate distance to line
        let distMeters = distanceFromPointToLine(p: userLoc, a: pin, b: boat)
        self.distanceToLine = distMeters

        // Calculate VMC toward line (improved)
        calculateVMCToLine()

        // Legacy time-to-burn (for backward compatibility)
        let targetSpeedKnots = sog < 1.0 ? accelConfig.targetSpeed : sog
        let speedMS = targetSpeedKnots / 1.94384
        let timeToTravel = distMeters / speedMS
        self.timeToBurn = secondsToStart - timeToTravel

        // Determine coaching phase (new system)
        determineStartPhase()
    }
    
    func distanceFromPointToLine(p: CLLocation, a: CLLocation, b: CLLocation) -> Double {
        let scaleLat = 111139.0
        let scaleLon = cos(p.coordinate.latitude * .pi / 180) * 111139.0
        let px = p.coordinate.longitude * scaleLon; let py = p.coordinate.latitude * scaleLat
        let ax = a.coordinate.longitude * scaleLon; let ay = a.coordinate.latitude * scaleLat
        let bx = b.coordinate.longitude * scaleLon; let by = b.coordinate.latitude * scaleLat
        let dx = bx - ax; let dy = by - ay
        if dx == 0 && dy == 0 { return 0 }
        let t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
        var nx: Double; var ny: Double
        if t < 0 { nx = ax; ny = ay } else if t > 1 { nx = bx; ny = by } else { nx = ax + t * dx; ny = ay + t * dy }
        return sqrt(pow(px - nx, 2) + pow(py - ny, 2))
    }

    /// Find the closest point on the start line segment to the user's position
    func closestPointOnLine(p: CLLocation, a: CLLocation, b: CLLocation) -> CLLocation {
        let scaleLat = 111139.0
        let scaleLon = cos(p.coordinate.latitude * .pi / 180) * 111139.0
        let px = p.coordinate.longitude * scaleLon; let py = p.coordinate.latitude * scaleLat
        let ax = a.coordinate.longitude * scaleLon; let ay = a.coordinate.latitude * scaleLat
        let bx = b.coordinate.longitude * scaleLon; let by = b.coordinate.latitude * scaleLat
        let dx = bx - ax; let dy = by - ay
        if dx == 0 && dy == 0 { return a }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
        let nx = ax + t * dx; let ny = ay + t * dy
        // Convert back to lat/lon
        let lon = nx / scaleLon
        let lat = ny / scaleLat
        return CLLocation(latitude: lat, longitude: lon)
    }

    /// Calculate VMC toward the closest point on the start line
    func calculateVMCToLine() {
        guard let userLoc = currentLocation, let boat = boatEnd, let pin = pinEnd else {
            vmcToLine = 0
            timeToLineVMC = 0
            return
        }

        // Find closest point on line
        let closestPoint = closestPointOnLine(p: userLoc, a: pin, b: boat)

        // Calculate bearing to closest point
        let bearingToLine = bearing(from: userLoc, to: closestPoint)

        // Calculate VMC = SOG × cos(angle difference)
        let angleDiff = (cog - bearingToLine) * .pi / 180
        vmcToLine = sog * cos(angleDiff)

        // Calculate time to line at current VMC
        let distMeters = distanceToLine
        if vmcToLine > 0.1 {  // Moving toward line
            let speedMS = vmcToLine / 1.94384  // knots to m/s
            timeToLineVMC = distMeters / speedMS
        } else if vmcToLine < -0.1 {  // Moving away from line
            // Negative time indicates moving away
            let speedMS = abs(vmcToLine) / 1.94384
            timeToLineVMC = -(distMeters / speedMS)
        } else {
            timeToLineVMC = Double.infinity  // Parallel to line
        }
    }

    /// Determine the current coaching phase based on position, speed, and timing
    func determineStartPhase() {
        guard boatEnd != nil, pinEnd != nil else {
            startPhase = .setup
            startStrategy = "SET LINE"
            return
        }

        // Race has started
        if secondsToStart < -60 {
            startPhase = .raceStarted
            startStrategy = "RACE STARTED"
            return
        }

        // Calculate key values
        let timeToLine = vmcToLine > 0.1 ? timeToLineVMC : Double.infinity
        let isApproaching = vmcToLine > 0.1
        let isReceding = vmcToLine < -0.1

        // Time margin (how early/late we'd arrive at current VMC)
        let arrivalMargin = secondsToStart - timeToLine

        // Calculate target reach distance
        targetReachDistance = accelConfig.targetReachDistance(availableTime: secondsToStart)

        // State machine for coaching phases
        if secondsToStart < 0 {
            // After gun
            if distanceToLine > 5 {
                startPhase = .late
                startStrategy = String(format: "LATE %.0fs", abs(secondsToStart))
            } else {
                startPhase = .go
                startStrategy = "GO!"
            }
        } else if secondsToStart <= accelConfig.timeToAccelerate + accelConfig.buffer {
            // Final approach phase - time to build speed and cross
            if isApproaching && timeToLine < secondsToStart + 2 {
                startPhase = .go
                startStrategy = String(format: "GO! %.0fs", secondsToStart)
            } else {
                startPhase = .build
                startStrategy = "BUILD SPEED"
            }
        } else if isApproaching && arrivalMargin < 0 {
            // Would arrive late at current pace
            startPhase = .build
            startStrategy = "BUILD SPEED"
        } else if isApproaching && arrivalMargin < accelConfig.timeToAccelerate {
            // Approaching with about right timing
            startPhase = .hold
            startStrategy = String(format: "HOLD %.0fs", arrivalMargin)
        } else if isApproaching && arrivalMargin > 30 && distanceToLine < 50 {
            // Too close, too early - need to slow down
            let targetSpeedKnots = max(1.0, distanceToLine / (secondsToStart - accelConfig.timeToAccelerate) * 1.94384)
            startPhase = .slowTo
            startStrategy = String(format: "SLOW TO %.1fkt", targetSpeedKnots)
        } else if isReceding && distanceToLine > targetReachDistance * 0.9 {
            // Reached far enough, time to turn back
            startPhase = .turnBack
            startStrategy = "TURN BACK"
        } else if !isApproaching && secondsToStart > 60 && distanceToLine < targetReachDistance * 0.8 {
            // Plenty of time, sail away to reach position
            startPhase = .reachTo
            startStrategy = String(format: "REACH TO %.0fm", targetReachDistance)
        } else if isApproaching {
            // Default approaching state - hold position
            startPhase = .hold
            startStrategy = String(format: "HOLD %.0fs", max(0, arrivalMargin))
        } else {
            // Not clearly approaching or receding - hold
            startPhase = .hold
            startStrategy = String(format: "HOLD %.0fs", max(0, secondsToStart - accelConfig.timeToAccelerate))
        }
    }
    
    // --- BUTTON ACTIONS ---
    func pingBoat() { boatEnd = currentLocation }
    func pingPin() { pinEnd = currentLocation }

    // --- VMC CALCULATIONS ---
    static let markRoundingDistance: Double = 30.48  // 100 feet in meters

    func calculateVMC() {
        guard let loc = currentLocation else { return }

        // Determine target based on race state
        let target: CLLocation?
        if currentLeg == 0 {
            // Pre-start: target is the midpoint of start line
            if let pin = pinEnd, let boat = boatEnd {
                let midLat = (pin.coordinate.latitude + boat.coordinate.latitude) / 2
                let midLon = (pin.coordinate.longitude + boat.coordinate.longitude) / 2
                target = CLLocation(latitude: midLat, longitude: midLon)
            } else {
                target = nil
            }
        } else {
            // Racing: target is the current mark (1-indexed)
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

        // Calculate bearing to target
        nextMarkBearing = bearing(from: loc, to: targetMark)

        // Calculate distance to target
        distanceToMark = loc.distance(from: targetMark)

        // Calculate VMC = SOG × cos(angle difference)
        let angleDiff = (cog - nextMarkBearing) * .pi / 180
        vmcToMark = sog * cos(angleDiff)

        // Auto-advance to next leg when within 100' of mark (but not for pre-start)
        if currentLeg > 0 && distanceToMark < Self.markRoundingDistance {
            advanceToNextLeg()
        }
    }

    /// Calculate bearing (degrees) from one location to another
    func bearing(from start: CLLocation, to end: CLLocation) -> Double {
        let lat1 = start.coordinate.latitude * .pi / 180
        let lat2 = end.coordinate.latitude * .pi / 180
        let dLon = (end.coordinate.longitude - start.coordinate.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        var bearing = atan2(y, x) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return bearing
    }

    /// Advance to next leg when mark is rounded
    func advanceToNextLeg() {
        if currentLeg < courseMarks.count {
            currentLeg += 1
        }
    }

    /// Reset to pre-start
    func resetToPreStart() {
        currentLeg = 0
    }
    
    // Quick Sync: Updates the TARGET time relative to NOW
    func syncTimer(minutes: Double) {
        targetTime = Date().addingTimeInterval(minutes * 60)
        updateTimerLogic()
    }
    
    func updateDisplay() {
        var target = (rawHeading + calibrationOffset).truncatingRemainder(dividingBy: 360)
        if target < 0 { target += 360 }
        let diff = target - displayHeading
        let shortestDiff = (diff + 540).truncatingRemainder(dividingBy: 360) - 180
        if abs(shortestDiff) > 180 { displayHeading = target } else { displayHeading += shortestDiff * 0.15 }
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

// MARK: - 2. THE UI
struct ContentView: View {
    @StateObject var compass = CompassViewModel()
    @StateObject var waypointStore = WaypointStore()
    @State private var startDragOffset: Double = 0.0
    @State private var mode: AppMode = .start
    @State private var showingCourseSetup = false

    enum AppMode { case start, race }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    
                    // TOP BAR
                    HStack {
                        Button(action: { mode = .start }) {
                            Text("START").bold()
                                .padding(10)
                                .background(mode == .start ? Color.black : Color.gray.opacity(0.1))
                                .foregroundColor(mode == .start ? .white : .black)
                                .cornerRadius(8)
                        }
                        Spacer()
                        if let wind = compass.trueWindDirection {
                            Text("WIND: \(Int(wind))°").font(.headline).bold()
                        }
                        Spacer()
                        Button(action: { mode = .race }) {
                            Text("RACE").bold()
                                .padding(10)
                                .background(mode == .race ? Color.black : Color.gray.opacity(0.1))
                                .foregroundColor(mode == .race ? .white : .black)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal).padding(.top, 10).frame(height: 50)
                    
                    if mode == .race { RaceView(compass: compass, geometry: geometry) }
                    else { StartView(compass: compass, waypointStore: waypointStore, showingCourseSetup: $showingCourseSetup, geometry: geometry) }
                }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .statusBar(hidden: true)
            .persistentSystemOverlays(.hidden)
            .preferredColorScheme(.light)  // Force light mode for high-contrast visibility
            .id(geometry.size)
            .gesture(DragGesture().onChanged { gesture in
                if mode == .race {
                    if !compass.isDragging { compass.isDragging = true; startDragOffset = compass.calibrationOffset }
                    compass.manualAdjust(newValue: startDragOffset + gesture.translation.width * 0.2)
                }
            }.onEnded { _ in compass.isDragging = false })
            .sheet(isPresented: $showingCourseSetup) {
                CourseSetupView(
                    waypointStore: waypointStore,
                    isPresented: $showingCourseSetup,
                    currentLocation: compass.currentLocation,
                    onCourseSet: { pinLocation, boatLocation in
                        compass.pinEnd = pinLocation
                        compass.boatEnd = boatLocation
                        // Update course marks for VMC calculations
                        compass.courseMarks = waypointStore.courseMarks.map { $0.location }
                        compass.resetToPreStart()
                    }
                )
            }
            .onAppear {
                // Restore course from saved waypoints on launch
                // Pin comes from portStart waypoint, stbd start from waypoint or auto-calculated
                if let portStart = waypointStore.portStart {
                    compass.pinEnd = portStart.location
                }
                if let stbdStart = waypointStore.stbdStartLocation() {
                    compass.boatEnd = stbdStart
                }
                // Load course marks for VMC calculations
                compass.courseMarks = waypointStore.courseMarks.map { $0.location }
                // Load acceleration config
                compass.accelConfig = waypointStore.accelConfig
            }
        }
    }
}

// --- RACE VIEW (Maximized for cockpit visibility) ---
struct RaceView: View {
    @ObservedObject var compass: CompassViewModel
    var geometry: GeometryProxy

    func calculateBubbleOffset(totalWidth: CGFloat) -> CGFloat {
        let safeAngle = max(-30.0, min(30.0, compass.heelAngle))
        let pixelsPerDegree = (totalWidth - 10.0) / 60.0
        return CGFloat(safeAngle) * pixelsPerDegree
    }

    // Format distance nicely
    func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f", meters)
        } else {
            return String(format: "%.1f", meters / 1852)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // LEFT COLUMN - BRG & VMC (30% width)
            VStack(spacing: 5) {
                // Bearing to mark
                VStack(spacing: 0) {
                    Text(String(format: "%03.0f", compass.nextMarkBearing))
                        .font(.system(size: geometry.size.height * 0.22, weight: .black, design: .monospaced))
                        .minimumScaleFactor(0.5)
                    Text("BRG")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(.gray)
                }

                Divider().padding(.horizontal, 10)

                // VMC
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", compass.vmcToMark))
                        .font(.system(size: geometry.size.height * 0.22, weight: .black, design: .monospaced))
                        .foregroundColor(compass.vmcToMark > 0 ? .green : .red)
                        .minimumScaleFactor(0.5)
                    Text("VMC")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(.gray)
                }

                Spacer()

                // COG at bottom
                VStack(spacing: 0) {
                    Text(String(format: "%03.0f", compass.cog))
                        .font(.system(size: geometry.size.height * 0.12, weight: .bold, design: .monospaced))
                    Text("COG")
                        .font(.system(size: geometry.size.height * 0.04, weight: .bold))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 10)
            }
            .frame(width: geometry.size.width * 0.28)

            // CENTER COLUMN - HEADING (40% width)
            VStack(spacing: 0) {
                // Layline indicator at top
                if compass.trueWindDirection != nil {
                    Group {
                        if compass.timeToLayline < -10 {
                            Text("OVER \(Int(abs(compass.timeToLayline)))s")
                                .foregroundColor(.red)
                        } else if compass.timeToLayline < 0 {
                            Text("TACK!")
                                .foregroundColor(.red)
                        } else {
                            Text("+\(Int(compass.timeToLayline))s")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.system(size: geometry.size.height * 0.08, weight: .black))
                    .frame(height: geometry.size.height * 0.12)
                }

                Spacer()

                // Main heading - as big as possible
                Text(String(format: "%03.0f", compass.displayHeading))
                    .font(.system(size: geometry.size.height * 0.45, weight: .black, design: .monospaced))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)

                Text("HDG")
                    .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                    .foregroundColor(.gray)

                Spacer()

                // Heel indicator
                VStack(spacing: 2) {
                    Text("\(Int(abs(compass.heelAngle)))°")
                        .font(.system(size: geometry.size.height * 0.10, weight: .bold, design: .monospaced))
                    Capsule().fill(Color.gray.opacity(0.3))
                        .frame(width: geometry.size.width * 0.20, height: 10)
                        .overlay(Circle().fill(Color.black).padding(1)
                            .offset(x: calculateBubbleOffset(totalWidth: geometry.size.width * 0.20)))
                }
                .padding(.bottom, 10)
            }
            .frame(width: geometry.size.width * 0.44)

            // RIGHT COLUMN - DIST, SOG, MARK (30% width)
            VStack(spacing: 5) {
                // Distance to mark
                VStack(spacing: 0) {
                    Text(formatDistance(compass.distanceToMark))
                        .font(.system(size: geometry.size.height * 0.18, weight: .black, design: .monospaced))
                        .minimumScaleFactor(0.5)
                    Text(compass.distanceToMark < 1000 ? "m" : "nm")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(.gray)
                }

                Divider().padding(.horizontal, 10)

                // SOG
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", compass.sog))
                        .font(.system(size: geometry.size.height * 0.18, weight: .black, design: .monospaced))
                        .minimumScaleFactor(0.5)
                    Text("SOG")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(.gray)
                }

                Spacer()

                // Next mark button
                Button(action: { compass.advanceToNextLeg() }) {
                    Text("MK\(compass.currentLeg + 1)")
                        .font(.system(size: geometry.size.height * 0.08, weight: .black))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.bottom, 10)
            }
            .frame(width: geometry.size.width * 0.28)
        }
    }
}

// --- START VIEW (Compact Layout for Landscape) ---
struct StartView: View {
    @ObservedObject var compass: CompassViewModel
    @ObservedObject var waypointStore: WaypointStore
    @Binding var showingCourseSetup: Bool
    var geometry: GeometryProxy

    // Helper to get waypoint name for display
    private func pinLabel() -> String {
        if let wp = waypointStore.portStart { return wp.name }
        return "PORT"
    }

    private func boatLabel() -> String {
        // Show waypoint name if manually set, otherwise "STBD"
        if let wp = waypointStore.stbdStart { return wp.name }
        return "STBD"
    }

    // Convert Remaining Seconds to MM:SS
    func timeString(seconds: Double) -> String {
        let totalSeconds = Int(ceil(seconds)) // Round up so 0.9s shows as 1s
        if totalSeconds <= 0 { return "0:00" }
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // Color coding for coach message background
    func coachBackgroundColor() -> Color {
        switch compass.startPhase {
        case .go:
            return .green
        case .late:
            return .red
        case .slowTo:
            return .orange
        case .build:
            return .purple
        case .turnBack:
            return .orange
        case .reachTo:
            return .blue
        case .hold:
            return .blue
        case .setup:
            return .gray
        case .raceStarted:
            return .gray
        }
    }

    // Format VMC to line with color indicator
    func vmcToLineColor() -> Color {
        if compass.vmcToLine > 0.5 {
            return .green   // Approaching line
        } else if compass.vmcToLine < -0.5 {
            return .blue    // Moving away (reaching)
        } else {
            return .orange  // Parallel / slow
        }
    }

    // Format ETA string
    func etaString() -> String {
        if compass.vmcToLine > 0.1 && compass.timeToLineVMC.isFinite && compass.timeToLineVMC > 0 {
            return String(format: "%.0fs", compass.timeToLineVMC)
        } else if compass.vmcToLine < -0.1 {
            return "AWAY"
        } else {
            return "---"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            
            // 1. WIND SETUP (12% Height)
            HStack(spacing: 10) {
                Button("SET STB") { compass.setStarboardTack() }
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(compass.starboardTackRef != nil ? Color.green : Color.orange)
                    .cornerRadius(8).foregroundColor(.white)
                    .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                
                Button("SET PORT") { compass.setPortTack() }
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(compass.portTackRef != nil ? Color.green : Color.orange)
                    .cornerRadius(8).foregroundColor(.white)
                    .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                
                Button("SET WIND") { compass.setWindDirectly() }
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(Color.blue).cornerRadius(8).foregroundColor(.white)
                    .font(.system(size: geometry.size.height * 0.05, weight: .bold))
            }
            .frame(height: geometry.size.height * 0.12)
            .frame(maxWidth: .infinity)
            
            // 2. FIXED TIME PICKER (12% Height)
            HStack {
                Text("START:")
                    .font(.system(size: geometry.size.height * 0.06, weight: .bold))
                    .foregroundColor(.gray)
                
                DatePicker("", selection: $compass.targetTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    // Scale the picker down slightly to fit tight spaces
                    .scaleEffect(0.8)
                    .colorInvert().colorMultiply(.black)
            }
            .frame(height: geometry.size.height * 0.12)
            
            // 3. COUNTDOWN TIMER (25% Height)
            Text(timeString(seconds: compass.secondsToStart))
                .font(.system(size: geometry.size.height * 0.25, weight: .black, design: .monospaced))
                .foregroundColor(compass.secondsToStart < 60 ? .red : .black)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .frame(height: geometry.size.height * 0.25)
            
            // 4. COACH MESSAGE (16% Height) - Enhanced two-line display
            VStack(spacing: 2) {
                // Primary message
                Text(compass.startStrategy)
                    .font(.system(size: geometry.size.height * 0.08, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Secondary info based on phase
                Group {
                    switch compass.startPhase {
                    case .build, .go:
                        // Show speed gauge during acceleration phases
                        HStack(spacing: 8) {
                            Text(String(format: "%.1f", compass.sog))
                                .font(.system(size: geometry.size.height * 0.04, weight: .bold, design: .monospaced))
                            Text("/")
                                .font(.system(size: geometry.size.height * 0.03))
                            Text(String(format: "%.1f kt", compass.accelConfig.targetSpeed))
                                .font(.system(size: geometry.size.height * 0.035, weight: .medium))
                        }
                        .foregroundColor(compass.sog >= compass.accelConfig.targetSpeed * 0.9 ? .white : .white.opacity(0.7))
                    case .hold, .slowTo:
                        Text(String(format: "VMC: %.1f kt", compass.vmcToLine))
                            .font(.system(size: geometry.size.height * 0.035, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    case .reachTo:
                        Text(String(format: "DIST: %.0fm", compass.distanceToLine))
                            .font(.system(size: geometry.size.height * 0.035, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(coachBackgroundColor())
            .cornerRadius(8)
            .padding(.vertical, 2)
            .frame(height: geometry.size.height * 0.16)
            
            // 5. STATS ROW (12% Height) - VMC→LINE, ETA, SOG
            HStack {
                VStack {
                    Text("VMC→LINE").font(.system(size: geometry.size.height * 0.030, weight: .bold)).foregroundColor(.gray)
                    Text(String(format: "%+.1f", compass.vmcToLine))
                        .font(.system(size: geometry.size.height * 0.055, weight: .bold, design: .monospaced))
                        .foregroundColor(vmcToLineColor())
                }
                Spacer()
                VStack {
                    Text("ETA").font(.system(size: geometry.size.height * 0.035, weight: .bold)).foregroundColor(.gray)
                    Text(etaString())
                        .font(.system(size: geometry.size.height * 0.055, weight: .bold, design: .monospaced))
                        .foregroundColor(compass.vmcToLine > 0 ? .green : .blue)
                }
                Spacer()
                VStack {
                    Text("SOG").font(.system(size: geometry.size.height * 0.035, weight: .bold)).foregroundColor(.gray)
                    Text(String(format: "%.1f", compass.sog))
                        .font(.system(size: geometry.size.height * 0.055, weight: .bold, design: .monospaced))
                }
                Spacer()
                VStack {
                    Text("DIST").font(.system(size: geometry.size.height * 0.035, weight: .bold)).foregroundColor(.gray)
                    Text(String(format: "%.0fm", compass.distanceToLine))
                        .font(.system(size: geometry.size.height * 0.055, weight: .bold, design: .monospaced))
                }
            }
            .padding(.horizontal, 20)
            .frame(height: geometry.size.height * 0.12)
            
            Spacer()
            
            // 6. BOTTOM BUTTONS (15% Height + Padding)
            HStack(spacing: 10) {
                // PIN - tap to GPS ping, long press opens course setup
                Button(action: { compass.pingPin() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "flag.fill").font(.system(size: geometry.size.height * 0.04))
                        Text(pinLabel())
                            .font(.system(size: geometry.size.height * 0.025, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth:.infinity, maxHeight:.infinity)
                    .background(compass.pinEnd == nil ? Color.orange : Color.green)
                    .foregroundColor(.white).cornerRadius(10)
                }

                // SET COURSE
                Button(action: { showingCourseSetup = true }) {
                    VStack(spacing: 2) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: geometry.size.height * 0.04))
                        Text("COURSE")
                            .font(.system(size: geometry.size.height * 0.025, weight: .bold))
                    }
                    .frame(maxWidth:.infinity, maxHeight:.infinity)
                    .background(Color.blue)
                    .foregroundColor(.white).cornerRadius(10)
                }

                // SYNC
                Button("5m") { compass.syncTimer(minutes: 5) }
                    .font(.system(size: geometry.size.height * 0.045, weight: .bold))
                    .frame(maxHeight:.infinity).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.2)).cornerRadius(10)

                Button("1m") { compass.syncTimer(minutes: 1) }
                    .font(.system(size: geometry.size.height * 0.045, weight: .bold))
                    .frame(maxHeight:.infinity).padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.2)).cornerRadius(10)

                // BOAT - tap to GPS ping
                Button(action: { compass.pingBoat() }) {
                    VStack(spacing: 2) {
                        Image(systemName: "sailboat.fill").font(.system(size: geometry.size.height * 0.04))
                        Text(boatLabel())
                            .font(.system(size: geometry.size.height * 0.025, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth:.infinity, maxHeight:.infinity)
                    .background(compass.boatEnd == nil ? Color.orange : Color.green)
                    .foregroundColor(.white).cornerRadius(10)
                }
            }
            .frame(height: geometry.size.height * 0.12)
            .padding(.horizontal)
            .padding(.bottom, 35) // Extra padding for home indicator
        }
    }
}

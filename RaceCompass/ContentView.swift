import SwiftUI
import CoreMotion
import CoreLocation
import Combine

// MARK: - 2. THE UI
struct ContentView: View {
    @StateObject var compass = CompassViewModel()
    @StateObject var waypointStore = WaypointStore()
    @EnvironmentObject var themeManager: ThemeManager
    @State private var startDragOffset: Double = 0.0
    @State private var mode: AppMode = .start
    @State private var showingCourseSetup = false
    @State private var showingSettings = false

    enum AppMode { case start, race }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                themeManager.currentTheme.background.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    
                    // TOP BAR
                    HStack {
                        Button(action: { mode = .start }) {
                            Text("START").bold()
                                .padding(10)
                                .background(mode == .start ? themeManager.currentTheme.tint : themeManager.currentTheme.secondaryText.opacity(0.2))
                                .foregroundColor(themeManager.currentTheme.background)
                                .cornerRadius(8)
                        }
                        Spacer()
                        if let wind = compass.trueWindDirection {
                            Text("WIND: \(Int(wind))°")
                                .font(.headline).bold()
                                .foregroundColor(themeManager.currentTheme.primaryText)
                        }
                        Spacer()

                        Button(action: { showingSettings = true }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                                .foregroundColor(themeManager.currentTheme.secondaryText)
                                .padding(.trailing, 10)
                        }

                        Button(action: { mode = .race }) {
                            Text("RACE").bold()
                                .padding(10)
                                .background(mode == .race ? themeManager.currentTheme.tint : themeManager.currentTheme.secondaryText.opacity(0.2))
                                .foregroundColor(themeManager.currentTheme.background)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal).padding(.top, 10).frame(height: 50)
                    .background(themeManager.currentTheme.topBarBackground)
                    
                    if mode == .race { RaceView(compass: compass, geometry: geometry) }
                    else { StartView(compass: compass, waypointStore: waypointStore, showingCourseSetup: $showingCourseSetup, geometry: geometry) }
                }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .statusBar(hidden: true)
            .persistentSystemOverlays(.hidden)
            .preferredColorScheme(themeManager.currentTheme.name == "Night" ? .dark : .light)
            .id(geometry.size)
            .gesture(DragGesture().onChanged { gesture in
                if mode == .race {
                    if !compass.isDragging { compass.isDragging = true; startDragOffset = compass.calibrationOffset }
                    compass.manualAdjust(newValue: startDragOffset + gesture.translation.width * 0.2)
                }
            }.onEnded { _ in compass.isDragging = false })
            .sheet(isPresented: $showingSettings, onDismiss: {
                compass.accelConfig = waypointStore.accelConfig
            }) {
                SettingsView(themeManager: themeManager, waypointStore: waypointStore, isPresented: $showingSettings)
            }
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
    @EnvironmentObject var themeManager: ThemeManager
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
                        .foregroundColor(themeManager.currentTheme.primaryText)
                        .minimumScaleFactor(0.5)
                    Text("BRG")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }

                Divider().background(themeManager.currentTheme.secondaryText).padding(.horizontal, 10)

                // VMC
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", compass.vmcToMark))
                        .font(.system(size: geometry.size.height * 0.22, weight: .black, design: .monospaced))
                        .foregroundColor(compass.vmcToMark > 0 ? themeManager.currentTheme.positive : themeManager.currentTheme.negative)
                        .minimumScaleFactor(0.5)
                    Text("VMC")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }

                Spacer()

                // COG at bottom
                VStack(spacing: 0) {
                    Text(String(format: "%03.0f", compass.cog))
                        .font(.system(size: geometry.size.height * 0.12, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.primaryText)
                    Text("COG")
                        .font(.system(size: geometry.size.height * 0.04, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
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
                                .foregroundColor(themeManager.currentTheme.negative)
                        } else if compass.timeToLayline < 0 {
                            Text("TACK!")
                                .foregroundColor(themeManager.currentTheme.negative)
                        } else {
                            Text("+\(Int(compass.timeToLayline))s")
                                .foregroundColor(themeManager.currentTheme.positive)
                        }
                    }
                    .font(.system(size: geometry.size.height * 0.08, weight: .black))
                    .frame(height: geometry.size.height * 0.12)
                }

                Spacer()

                // Main heading - as big as possible
                Text(String(format: "%03.0f", compass.displayHeading))
                    .font(.system(size: geometry.size.height * 0.45, weight: .black, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.primaryText)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("HDG")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                    if compass.headingWarning != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: geometry.size.height * 0.04))
                            .foregroundColor(themeManager.currentTheme.warning)
                    }
                }

                Spacer()

                // Heel indicator
                VStack(spacing: 2) {
                    Text("\(Int(abs(compass.heelAngle)))°")
                        .font(.system(size: geometry.size.height * 0.10, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.primaryText)
                    Capsule().fill(themeManager.currentTheme.secondaryText.opacity(0.3))
                        .frame(width: geometry.size.width * 0.20, height: 10)
                        .overlay(Circle().fill(themeManager.currentTheme.bubbleFill).padding(1)
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
                        .foregroundColor(themeManager.currentTheme.primaryText)
                        .minimumScaleFactor(0.5)
                    Text(compass.distanceToMark < 1000 ? "m" : "nm")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }

                Divider().background(themeManager.currentTheme.secondaryText).padding(.horizontal, 10)

                // SOG
                VStack(spacing: 0) {
                    Text(String(format: "%.1f", compass.sog))
                        .font(.system(size: geometry.size.height * 0.18, weight: .black, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.primaryText)
                        .minimumScaleFactor(0.5)
                    Text("SOG")
                        .font(.system(size: geometry.size.height * 0.05, weight: .bold))
                        .foregroundColor(themeManager.currentTheme.secondaryText)
                }

                Spacer()

                // Next mark button
                Button(action: { compass.advanceToNextLeg() }) {
                    Text("MK\(compass.currentLeg + 1)")
                        .font(.system(size: geometry.size.height * 0.08, weight: .black))
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(themeManager.currentTheme.warning)
                        .foregroundColor(themeManager.currentTheme.bubbleText)
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
    @EnvironmentObject var themeManager: ThemeManager
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

    // Convert Remaining Seconds to MM:SS (countdown)
    func timeString(seconds: Double) -> String {
        let totalSeconds = Int(ceil(seconds)) // Round up so 0.9s shows as 1s
        if totalSeconds <= 0 { return "0:00" }
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // Convert Elapsed Seconds to MM:SS (count up)
    func elapsedTimeString(seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // Color coding for coach message background
    func coachBackgroundColor() -> Color {
        let theme = themeManager.currentTheme
        switch compass.startPhase {
        case .go:
            return theme.positive
        case .late:
            return theme.negative
        case .slowTo:
            return theme.warning
        case .build:
            return theme.tint
        case .turnBack:
            return theme.warning
        case .reachTo:
            return theme.tint
        case .hold:
            return theme.tint
        case .setup:
            return theme.secondaryText
        case .raceStarted:
            return theme.secondaryText
        }
    }

    // Format VMC to line with color indicator
    func vmcToLineColor() -> Color {
        if compass.vmcToLine > 0.5 {
            return themeManager.currentTheme.positive   // Approaching line
        } else if compass.vmcToLine < -0.5 {
            return themeManager.currentTheme.tint    // Moving away (reaching)
        } else {
            return themeManager.currentTheme.warning  // Parallel / slow
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
                    .background(compass.starboardTackRef != nil ? themeManager.currentTheme.positive : themeManager.currentTheme.warning)
                    .cornerRadius(8).foregroundColor(themeManager.currentTheme.bubbleText)
                    .font(.system(size: geometry.size.height * 0.05, weight: .bold))

                Button("SET PORT") { compass.setPortTack() }
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(compass.portTackRef != nil ? themeManager.currentTheme.positive : themeManager.currentTheme.warning)
                    .cornerRadius(8).foregroundColor(themeManager.currentTheme.bubbleText)
                    .font(.system(size: geometry.size.height * 0.05, weight: .bold))

                Button("SET WIND") { compass.setWindDirectly() }
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(themeManager.currentTheme.tint).cornerRadius(8).foregroundColor(themeManager.currentTheme.bubbleText)
                    .font(.system(size: geometry.size.height * 0.05, weight: .bold))

                // Warning if heading is magnetic without declination
                if compass.headingWarning != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: geometry.size.height * 0.05))
                        .foregroundColor(themeManager.currentTheme.warning)
                }
            }
            .frame(height: geometry.size.height * 0.12)
            .frame(maxWidth: .infinity)
            
            // 2. FIXED TIME PICKER (12% Height)
            HStack {
                Text("START:")
                    .font(.system(size: geometry.size.height * 0.06, weight: .bold))
                    .foregroundColor(themeManager.currentTheme.secondaryText)
                
                DatePicker("", selection: $compass.targetTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    // Scale the picker down slightly to fit tight spaces
                    .scaleEffect(0.8)
                    .colorInvert().colorMultiply(themeManager.currentTheme.primaryText)
            }
            .frame(height: geometry.size.height * 0.12)
            
            // 3. COUNTDOWN / RACE TIMER (25% Height)
            if compass.secondsToStart > 0 {
                // Countdown to start
                Text(timeString(seconds: compass.secondsToStart))
                    .font(.system(size: geometry.size.height * 0.25, weight: .black, design: .monospaced))
                    .foregroundColor(compass.secondsToStart < 60 ? themeManager.currentTheme.negative : themeManager.currentTheme.primaryText)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .frame(height: geometry.size.height * 0.25)
            } else {
                // Race elapsed timer with stop/start
                HStack(spacing: 15) {
                    Text(elapsedTimeString(seconds: compass.raceElapsedTime))
                        .font(.system(size: geometry.size.height * 0.22, weight: .black, design: .monospaced))
                        .foregroundColor(compass.isRaceTimerRunning ? themeManager.currentTheme.positive : themeManager.currentTheme.warning)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Button(action: { compass.toggleRaceTimer() }) {
                        Image(systemName: compass.isRaceTimerRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: geometry.size.height * 0.08, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.bubbleText)
                            .frame(width: geometry.size.height * 0.12, height: geometry.size.height * 0.12)
                            .background(themeManager.currentTheme.tint)
                            .cornerRadius(8)
                    }
                }
                .frame(height: geometry.size.height * 0.25)
            }
            
            // 4. COACH MESSAGE (16% Height) - Enhanced two-line display
            VStack(spacing: 2) {
                // Primary message
                Text(compass.startStrategy)
                    .font(.system(size: geometry.size.height * 0.08, weight: .heavy))
                    .foregroundColor(themeManager.currentTheme.bubbleText)
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
                        .foregroundColor(compass.sog >= compass.accelConfig.targetSpeed * 0.9 ? themeManager.currentTheme.bubbleText : themeManager.currentTheme.bubbleText.opacity(0.7))
                    case .hold, .slowTo:
                        // Show bearing to line when approaching
                        if compass.vmcToLine > 0.1 {
                            Text(String(format: "LINE %03.0f° • VMC %.1f kt", compass.bearingToLine, compass.vmcToLine))
                                .font(.system(size: geometry.size.height * 0.035, weight: .medium))
                                .foregroundColor(themeManager.currentTheme.bubbleText.opacity(0.9))
                        } else {
                            Text(String(format: "VMC: %.1f kt", compass.vmcToLine))
                                .font(.system(size: geometry.size.height * 0.035, weight: .medium))
                                .foregroundColor(themeManager.currentTheme.bubbleText.opacity(0.9))
                        }
                    case .reachTo:
                        if compass.portApproachRecommended {
                            Text(String(format: "PIN +%.0fm • PORT APPROACH", compass.lineBias))
                                .font(.system(size: geometry.size.height * 0.032, weight: .medium))
                                .foregroundColor(themeManager.currentTheme.bubbleText.opacity(0.9))
                        } else {
                            Text(String(format: "%.0fm / %.0fm", compass.distanceAlongLine, compass.targetReachDistance))
                                .font(.system(size: geometry.size.height * 0.035, weight: .medium))
                                .foregroundColor(themeManager.currentTheme.bubbleText.opacity(0.9))
                        }
                    case .turnBack:
                        // Show bearing to line prominently when turning back
                        Text(String(format: "STEER %03.0f° TO LINE", compass.bearingToLine))
                            .font(.system(size: geometry.size.height * 0.04, weight: .bold))
                            .foregroundColor(themeManager.currentTheme.bubbleText)
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
            
            // 5. STATS ROW (12% Height) - VMC (m/s), BURN, DIST
            HStack {
                VStack {
                    Text("VMC").font(.system(size: geometry.size.height * 0.035, weight: .bold)).foregroundColor(themeManager.currentTheme.secondaryText)
                    // Convert knots to m/s for easier mental math with distance in meters
                    Text(String(format: "%+.1f", compass.vmcToLine / 1.94384))
                        .font(.system(size: geometry.size.height * 0.055, weight: .bold, design: .monospaced))
                        .foregroundColor(vmcToLineColor())
                }
                Spacer()
                VStack {
                    Text("BURN").font(.system(size: geometry.size.height * 0.035, weight: .bold)).foregroundColor(themeManager.currentTheme.secondaryText)
                    Text(String(format: "%+.0fs", compass.timeToBurn))
                        .font(.system(size: geometry.size.height * 0.055, weight: .bold, design: .monospaced))
                        .foregroundColor(compass.timeToBurn > 0 ? themeManager.currentTheme.positive : themeManager.currentTheme.negative)
                }
                Spacer()
                VStack {
                    Text("DIST").font(.system(size: geometry.size.height * 0.035, weight: .bold)).foregroundColor(themeManager.currentTheme.secondaryText)
                    Text(String(format: "%.0fm", compass.distanceToLine))
                        .font(.system(size: geometry.size.height * 0.055, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.primaryText)
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
                    .background(compass.pinEnd == nil ? themeManager.currentTheme.warning : themeManager.currentTheme.positive)
                    .foregroundColor(themeManager.currentTheme.bubbleText).cornerRadius(10)
                }

                // SET COURSE
                Button(action: { showingCourseSetup = true }) {
                    VStack(spacing: 2) {
                        Image(systemName: "mappin.and.ellipse").font(.system(size: geometry.size.height * 0.04))
                        Text("COURSE")
                            .font(.system(size: geometry.size.height * 0.025, weight: .bold))
                    }
                    .frame(maxWidth:.infinity, maxHeight:.infinity)
                    .background(themeManager.currentTheme.tint)
                    .foregroundColor(themeManager.currentTheme.bubbleText).cornerRadius(10)
                }

                // SYNC
                Button("5m") { compass.syncTimer(minutes: 5) }
                    .font(.system(size: geometry.size.height * 0.045, weight: .bold))
                    .frame(maxHeight:.infinity).padding(.horizontal, 8)
                    .background(themeManager.currentTheme.secondaryText.opacity(0.2)).cornerRadius(10)
                    .foregroundColor(themeManager.currentTheme.primaryText)

                Button("1m") { compass.syncTimer(minutes: 1) }
                    .font(.system(size: geometry.size.height * 0.045, weight: .bold))
                    .frame(maxHeight:.infinity).padding(.horizontal, 8)
                    .background(themeManager.currentTheme.secondaryText.opacity(0.2)).cornerRadius(10)
                    .foregroundColor(themeManager.currentTheme.primaryText)

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
                    .background(compass.boatEnd == nil ? themeManager.currentTheme.warning : themeManager.currentTheme.positive)
                    .foregroundColor(themeManager.currentTheme.bubbleText).cornerRadius(10)
                }
            }
            .frame(height: geometry.size.height * 0.12)
            .padding(.horizontal)
            .padding(.bottom, 35) // Extra padding for home indicator
        }
    }
}

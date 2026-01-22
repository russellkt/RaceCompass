import SwiftUI
import CoreMotion
import CoreLocation
import Combine

// MARK: - 1. THE LOGIC (Unchanged)
class CompassViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    
    // UI Variables
    @Published var displayHeading: Double = 0.0
    @Published var calibrationOffset: Double = 0.0
    @Published var isDragging: Bool = false
    
    // GPS Variables
    @Published var sog: Double = 0.0
    @Published var cog: Double = 0.0
    @Published var hasGPSFix: Bool = false
    
    // Heel Variable
    @Published var heelAngle: Double = 0.0
    
    // Internal calculations
    private var rawHeading: Double = 0.0
    
    override init() {
        super.init()
        startSensorFusion()
        startGPS()
    }
    
    func startSensorFusion() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 20.0
        
        motionManager.startDeviceMotionUpdates(
            using: .xMagneticNorthZVertical,
            to: .main
        ) { [weak self] (motion, error) in
            guard let self = self, let motion = motion else { return }
            
            // Heading
            let azimuth = motion.attitude.yaw
            var degrees = -azimuth * (180.0 / .pi)
            if degrees < 0 { degrees += 360 }
            self.rawHeading = degrees
            
            // Heel (Pitch for Landscape)
            let pitch = motion.attitude.pitch
            self.heelAngle = pitch * (180.0 / .pi)
            
            if !self.isDragging {
                self.updateDisplay()
            }
        }
    }
    
    func startGPS() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        if location.speed >= 0 { self.sog = location.speed * 1.94384 }
        if location.course >= 0 { self.cog = location.course }
    }
    
    func updateDisplay() {
        var target = (rawHeading + calibrationOffset).truncatingRemainder(dividingBy: 360)
        if target < 0 { target += 360 }
        
        let diff = target - displayHeading
        let shortestDiff = (diff + 540).truncatingRemainder(dividingBy: 360) - 180
        
        if abs(shortestDiff) > 180 {
            displayHeading = target
        } else {
            displayHeading += shortestDiff * 0.15
        }
        
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

// MARK: - 2. THE UI (Integrated Heel Bar)
struct ContentView: View {
    @StateObject var compass = CompassViewModel()
    @State private var startDragOffset: Double = 0.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    
                    // --- TOP: HEADING (MAXIMIZED 70% Height) ---
                    // Since the middle bar is gone, we can make this even bigger.
                    VStack(spacing: 0) {
                        Spacer()
                        Text(String(format: "%03.0f", compass.displayHeading))
                            .font(.system(
                                size: geometry.size.height * 0.70, // 70% of screen height
                                weight: .black,
                                design: .monospaced
                            ))
                            .foregroundColor(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity)
                        
                        Text(compass.isDragging ? "CALIBRATING..." : "HEADING")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(compass.isDragging ? .red : .gray)
                            .offset(y: -10)
                    }
                    .frame(height: geometry.size.height * 0.70)
                    
                    
                    // --- BOTTOM: COG | HEEL (VISUAL + NUMERIC) | SOG ---
                    // Takes up bottom 30%
                    HStack(alignment: .center, spacing: 0) {
                        
                        // LEFT: COG
                        VStack(spacing: 0) {
                            Text("COG")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text(String(format: "%03.0f", compass.cog))
                                .font(.system(size: geometry.size.height * 0.20, weight: .black, design: .monospaced))
                                .foregroundColor(.black)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(width: geometry.size.width * 0.25) // 25% Width
                        
                        
                        // CENTER: HEEL COMPLEX (Number + Bubble)
                        VStack(spacing: 5) {
                            
                            // 1. The Number
                            Text("\(Int(abs(compass.heelAngle)))°")
                                .font(.system(size: geometry.size.height * 0.15, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                            
                            // 2. The Bubble Bar (Compact)
                            ZStack {
                                // Track
                                Capsule()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: geometry.size.width * 0.4, height: 12)
                                
                                // Center Mark
                                Rectangle()
                                    .fill(Color.gray)
                                    .frame(width: 2, height: 20)
                                
                                // The Dot
                                let maxAngle: Double = 30.0
                                let barWidth = geometry.size.width * 0.4
                                let clampedHeel = max(-maxAngle, min(maxAngle, compass.heelAngle))
                                let xOffset = (clampedHeel / maxAngle) * (barWidth / 2)
                                
                                Circle()
                                    .fill(Color.black)
                                    .frame(width: 20, height: 20)
                                    .offset(x: xOffset)
                            }
                        }
                        .frame(width: geometry.size.width * 0.50) // 50% Width (Give it room to swing)

                        
                        // RIGHT: SOG
                        VStack(spacing: 0) {
                            Text("SOG")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.gray)
                            Text(String(format: "%.1f", compass.sog))
                                .font(.system(size: geometry.size.height * 0.20, weight: .black, design: .monospaced))
                                .foregroundColor(.black)
                                .minimumScaleFactor(0.5)
                        }
                        .frame(width: geometry.size.width * 0.25) // 25% Width
                        
                    }
                    .frame(height: geometry.size.height * 0.30)
                    .padding(.bottom, 10)
                }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .statusBar(hidden: true)
            .id(geometry.size)
            
            // Drag Gesture
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if !compass.isDragging {
                            compass.isDragging = true
                            startDragOffset = compass.calibrationOffset
                        }
                        let sensitivity = 0.2
                        let dragAmount = gesture.translation.width * sensitivity
                        compass.manualAdjust(newValue: startDragOffset + dragAmount)
                    }
                    .onEnded { _ in
                        compass.isDragging = false
                    }
            )
        }
    }
}

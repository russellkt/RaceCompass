import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var sog: Double = 0.0 // Knots
    @Published var cog: Double = 0.0 // Degrees True
    @Published var magneticDeclination: Double? = nil // Degrees (True - Magnetic)

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
    }

    func start() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Calculate magnetic declination from the difference between true and magnetic heading
        if newHeading.trueHeading >= 0 && newHeading.magneticHeading >= 0 {
            var declination = newHeading.trueHeading - newHeading.magneticHeading
            // Normalize to -180 to 180
            if declination > 180 { declination -= 360 }
            if declination < -180 { declination += 360 }
            self.magneticDeclination = declination
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.currentLocation = location

        // Speed is in m/s, convert to knots
        if location.speed >= 0 {
            self.sog = location.speed * Constants.metersPerSecondToKnots
        }

        // Course is in degrees true
        if location.course >= 0 {
            self.cog = location.course
        }
    }
}

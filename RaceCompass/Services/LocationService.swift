import Foundation
import CoreLocation
import Combine

class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var sog: Double = 0.0 // Knots
    @Published var cog: Double = 0.0 // Degrees True

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
    }

    func start() {
        locationManager.startUpdatingLocation()
    }

    func stop() {
        locationManager.stopUpdatingLocation()
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

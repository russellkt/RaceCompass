import Foundation
import Combine
import CoreLocation

class WaypointStore: ObservableObject {
    @Published var waypoints: [Waypoint] = []
    @Published var courseSetup: CourseSetup = CourseSetup()

    private let waypointsKey = "savedWaypoints"
    private let courseKey = "savedCourse"
    private let parser = GPXParser()

    init() {
        loadWaypoints()
        loadCourseSetup()
    }

    // MARK: - Waypoint Management

    func add(_ waypoint: Waypoint) {
        // Avoid duplicates by name and location
        if !waypoints.contains(where: { $0.name == waypoint.name &&
            abs($0.latitude - waypoint.latitude) < 0.0001 &&
            abs($0.longitude - waypoint.longitude) < 0.0001 }) {
            waypoints.append(waypoint)
            saveWaypoints()
        }
    }

    /// Create a new waypoint from current GPS location
    func addFromLocation(_ location: CLLocation, name: String? = nil) -> Waypoint {
        let waypointName = name ?? "Mark \(waypoints.count + 1)"
        let waypoint = Waypoint(
            name: waypointName,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        waypoints.append(waypoint)
        saveWaypoints()
        return waypoint
    }

    func remove(_ waypoint: Waypoint) {
        waypoints.removeAll { $0.id == waypoint.id }
        // Also remove from course if assigned
        if courseSetup.portStartId == waypoint.id {
            courseSetup.portStartId = nil
        }
        if courseSetup.endPinId == waypoint.id {
            courseSetup.endPinId = nil
        }
        courseSetup.markIds.removeAll { $0 == waypoint.id }
        saveWaypoints()
        saveCourseSetup()
    }

    func removeAll() {
        waypoints.removeAll()
        courseSetup = CourseSetup()
        saveWaypoints()
        saveCourseSetup()
    }

    // MARK: - GPX Import

    func importGPX(from url: URL) -> Int {
        // Handle security-scoped resource access
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        guard let imported = parser.parse(url: url) else { return 0 }

        var addedCount = 0
        for waypoint in imported {
            let beforeCount = waypoints.count
            add(waypoint)
            if waypoints.count > beforeCount { addedCount += 1 }
        }
        return addedCount
    }

    // MARK: - Course Setup

    func setPortStart(_ waypoint: Waypoint?) {
        courseSetup.setPortStart(waypoint)
        saveCourseSetup()
    }

    func setStbdStart(_ waypoint: Waypoint?) {
        courseSetup.setStbdStart(waypoint)
        saveCourseSetup()
    }

    func setEndPin(_ waypoint: Waypoint?) {
        courseSetup.setEndPin(waypoint)
        saveCourseSetup()
    }

    func addCourseMark(_ waypoint: Waypoint) {
        courseSetup.addMark(waypoint)
        saveCourseSetup()
    }

    func removeCourseMark(at index: Int) {
        courseSetup.removeMark(at: index)
        saveCourseSetup()
    }

    func reorderCourseMarks(_ newOrder: [UUID]) {
        courseSetup.reorderMarks(newOrder)
        saveCourseSetup()
    }

    var portStart: Waypoint? {
        courseSetup.portStart(in: waypoints)
    }

    /// Manual stbd start waypoint (nil if using auto-calculation)
    var stbdStart: Waypoint? {
        courseSetup.stbdStart(in: waypoints)
    }

    /// Returns true if stbd start is manually set (not auto-calculated)
    var isStbdStartManual: Bool {
        courseSetup.stbdStartId != nil
    }

    var endPin: Waypoint? {
        courseSetup.endPin(in: waypoints)
    }

    var courseMarks: [Waypoint] {
        courseSetup.marks(in: waypoints)
    }

    var firstMark: Waypoint? {
        courseSetup.firstMark(in: waypoints)
    }

    func clearCourse() {
        courseSetup = CourseSetup()
        saveCourseSetup()
    }

    // MARK: - Start Line Calculation

    /// Line length in feet (pin to boat end) when auto-calculating
    static let startLineLength: Double = 50.0

    /// Get stbd start location - either from manual waypoint or auto-calculated
    func stbdStartLocation() -> CLLocation? {
        // If manually set, use that waypoint
        if let manual = stbdStart {
            return manual.location
        }
        // Otherwise auto-calculate
        return autoCalculatedStbdStart()
    }

    /// Auto-calculate the stbd start (RC boat) position: 50' perpendicular (to starboard/right)
    /// of the portStart→firstMark bearing
    func autoCalculatedStbdStart() -> CLLocation? {
        guard let pin = portStart,
              let firstMark = firstMark else { return nil }

        let pinLoc = pin.location
        let firstMarkLoc = firstMark.location

        // Calculate bearing from pin to first mark
        let bearing = Self.bearing(from: pinLoc, to: firstMarkLoc)

        // Stbd start is 90° to starboard (right) of that bearing
        let stbdBearing = (bearing + 90).truncatingRemainder(dividingBy: 360)

        // Calculate point 50 feet from pin along that bearing
        let distanceMeters = Self.startLineLength * 0.3048 // feet to meters
        return Self.destination(from: pinLoc, bearing: stbdBearing, distanceMeters: distanceMeters)
    }

    /// Calculate bearing (in degrees) from one location to another
    static func bearing(from start: CLLocation, to end: CLLocation) -> Double {
        let lat1 = start.coordinate.latitude * .pi / 180
        let lat2 = end.coordinate.latitude * .pi / 180
        let dLon = (end.coordinate.longitude - start.coordinate.longitude) * .pi / 180

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        var bearing = atan2(y, x) * 180 / .pi
        if bearing < 0 { bearing += 360 }
        return bearing
    }

    /// Calculate destination point given start, bearing, and distance
    static func destination(from start: CLLocation, bearing: Double, distanceMeters: Double) -> CLLocation {
        let earthRadius = 6371000.0 // meters
        let lat1 = start.coordinate.latitude * .pi / 180
        let lon1 = start.coordinate.longitude * .pi / 180
        let bearingRad = bearing * .pi / 180
        let angularDist = distanceMeters / earthRadius

        let lat2 = asin(sin(lat1) * cos(angularDist) + cos(lat1) * sin(angularDist) * cos(bearingRad))
        let lon2 = lon1 + atan2(sin(bearingRad) * sin(angularDist) * cos(lat1),
                                 cos(angularDist) - sin(lat1) * sin(lat2))

        return CLLocation(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    // MARK: - Persistence

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var waypointsFileURL: URL {
        documentsURL.appendingPathComponent("waypoints.json")
    }

    private var courseFileURL: URL {
        documentsURL.appendingPathComponent("course.json")
    }

    private func saveWaypoints() {
        do {
            let data = try JSONEncoder().encode(waypoints)
            try data.write(to: waypointsFileURL)
        } catch {
            print("Failed to save waypoints: \(error)")
        }
    }

    private func loadWaypoints() {
        do {
            let data = try Data(contentsOf: waypointsFileURL)
            waypoints = try JSONDecoder().decode([Waypoint].self, from: data)
        } catch {
            waypoints = []
        }
    }

    private func saveCourseSetup() {
        do {
            let data = try JSONEncoder().encode(courseSetup)
            try data.write(to: courseFileURL)
        } catch {
            print("Failed to save course: \(error)")
        }
    }

    private func loadCourseSetup() {
        do {
            let data = try Data(contentsOf: courseFileURL)
            courseSetup = try JSONDecoder().decode(CourseSetup.self, from: data)
        } catch {
            courseSetup = CourseSetup()
        }
    }
}

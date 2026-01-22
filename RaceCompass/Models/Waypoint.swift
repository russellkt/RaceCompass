import Foundation
import CoreLocation

struct Waypoint: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var latitude: Double
    var longitude: Double

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Course structure:
/// - portStart: Pin end of start line (waypoint)
/// - stbdStart: Boat end (auto-calculated 50' perpendicular to first mark bearing)
/// - marks: Ordered list of course marks (first one determines start line angle)
/// - endPin: Finish mark
struct CourseSetup: Codable {
    var portStartId: UUID?      // Pin end waypoint (port side of start line)
    var stbdStartId: UUID?      // RC boat waypoint (nil = auto-calculate 50' from port)
    var markIds: [UUID] = []    // Ordered course marks (first = windward for start line calc)
    var endPinId: UUID?         // Finish mark

    mutating func setPortStart(_ waypoint: Waypoint?) {
        portStartId = waypoint?.id
    }

    mutating func setStbdStart(_ waypoint: Waypoint?) {
        stbdStartId = waypoint?.id
    }

    mutating func setEndPin(_ waypoint: Waypoint?) {
        endPinId = waypoint?.id
    }

    func stbdStart(in waypoints: [Waypoint]) -> Waypoint? {
        guard let id = stbdStartId else { return nil }
        return waypoints.first { $0.id == id }
    }

    mutating func addMark(_ waypoint: Waypoint) {
        if !markIds.contains(waypoint.id) {
            markIds.append(waypoint.id)
        }
    }

    mutating func removeMark(at index: Int) {
        guard index >= 0 && index < markIds.count else { return }
        markIds.remove(at: index)
    }

    mutating func reorderMarks(_ newOrder: [UUID]) {
        markIds = newOrder
    }

    func portStart(in waypoints: [Waypoint]) -> Waypoint? {
        guard let id = portStartId else { return nil }
        return waypoints.first { $0.id == id }
    }

    func endPin(in waypoints: [Waypoint]) -> Waypoint? {
        guard let id = endPinId else { return nil }
        return waypoints.first { $0.id == id }
    }

    func marks(in waypoints: [Waypoint]) -> [Waypoint] {
        markIds.compactMap { id in waypoints.first { $0.id == id } }
    }

    /// First mark determines the start line angle
    func firstMark(in waypoints: [Waypoint]) -> Waypoint? {
        guard let firstId = markIds.first else { return nil }
        return waypoints.first { $0.id == firstId }
    }
}

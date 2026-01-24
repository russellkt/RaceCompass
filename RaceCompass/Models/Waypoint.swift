import Foundation
import CoreLocation

// MARK: - Start Phase Coaching

/// Phases for the improved start coaching system
enum StartPhase: String, Codable {
    case setup = "SET LINE"           // No line set
    case reachTo = "REACH TO"         // Far out, time to spare - sailing away from line
    case turnBack = "TURN BACK"       // Reached far enough, time to head back
    case hold = "HOLD"                // Good position, burning time
    case slowTo = "SLOW TO"           // Too close, too fast
    case build = "BUILD SPEED"        // Time to accelerate
    case go = "GO!"                   // Final approach
    case late = "LATE"                // Missed timing
    case raceStarted = "RACE STARTED" // Timer went negative
}

/// Configuration for acceleration and speed parameters
struct AccelerationConfig: Codable {
    var timeToAccelerate: Double = 12.0    // seconds to reach target speed
    var targetSpeed: Double = 5.0           // target crossing speed (knots)
    var reachingSpeedMultiplier: Double = 1.3  // reaching is typically 30% faster than upwind
    var buffer: Double = 3.0                // safety buffer (seconds)

    /// Calculate target reach distance based on available time and recorded upwind speed
    /// - Parameters:
    ///   - availableTime: seconds until start
    ///   - recordedUpwindSOG: measured upwind speed in knots (learned from sailing close-hauled)
    func targetReachDistance(availableTime: Double, recordedUpwindSOG: Double = 5.0) -> Double {
        guard availableTime > 0 else { return 0 }

        // Time available for reaching maneuver (minus acceleration and buffer)
        let reachTime = availableTime - timeToAccelerate - buffer
        guard reachTime > 0 else { return 0 }

        // Use recorded upwind SOG if valid, otherwise fall back to configured target speed
        let returnSpeedKnots = recordedUpwindSOG > 1.0 ? recordedUpwindSOG : max(1.0, targetSpeed)
        let reachSpeedKnots = returnSpeedKnots * reachingSpeedMultiplier

        let reachSpeedMS = reachSpeedKnots / 1.94384  // knots to m/s
        let returnSpeedMS = returnSpeedKnots / 1.94384

        // Time to travel X meters out and back = X/reachSpeed + X/returnSpeed
        // So X = reachTime / (1/reachSpeed + 1/returnSpeed)
        let distance = reachTime / (1/reachSpeedMS + 1/returnSpeedMS) * 0.8  // 80% safety factor
        return max(0, distance)
    }

    /// Calculate total time needed for the reach maneuver (out + back + accel + buffer)
    /// - Parameters:
    ///   - distance: target reach distance in meters
    ///   - recordedUpwindSOG: measured upwind speed in knots (learned from sailing close-hauled)
    /// - Returns: total seconds needed
    func maneuverTime(forDistance distance: Double, recordedUpwindSOG: Double = 5.0) -> Double {
        guard distance > 0 else { return timeToAccelerate + buffer }

        // Use recorded upwind SOG if valid, otherwise fall back to configured target speed
        let returnSpeedKnots = recordedUpwindSOG > 1.0 ? recordedUpwindSOG : max(1.0, targetSpeed)
        let reachSpeedKnots = returnSpeedKnots * reachingSpeedMultiplier

        let reachSpeedMS = reachSpeedKnots / 1.94384
        let returnSpeedMS = returnSpeedKnots / 1.94384

        let timeOut = distance / reachSpeedMS
        let timeBack = distance / returnSpeedMS

        return timeOut + timeBack + timeToAccelerate + buffer
    }
}

// MARK: - Waypoint Model

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

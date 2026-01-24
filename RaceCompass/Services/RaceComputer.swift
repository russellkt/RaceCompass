import Foundation
import CoreLocation

struct RaceComputer {

    // MARK: - Geometry

    /// Calculate bearing (degrees) from one location to another (Great Circle)
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

    /// Calculate distance from point P to line segment AB
    static func distanceFromPointToLine(p: CLLocation, a: CLLocation, b: CLLocation) -> Double {
        // Project to flat plane for short distances (Start Line is < 1km)
        let scaleLat = Constants.metersPerDegreeLatitude
        let scaleLon = cos(p.coordinate.latitude * .pi / 180) * Constants.metersPerDegreeLatitude

        let px = p.coordinate.longitude * scaleLon
        let py = p.coordinate.latitude * scaleLat
        let ax = a.coordinate.longitude * scaleLon
        let ay = a.coordinate.latitude * scaleLat
        let bx = b.coordinate.longitude * scaleLon
        let by = b.coordinate.latitude * scaleLat

        let dx = bx - ax
        let dy = by - ay

        if dx == 0 && dy == 0 { return 0 }

        let t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)

        var nx: Double
        var ny: Double

        if t < 0 {
            nx = ax
            ny = ay
        } else if t > 1 {
            nx = bx
            ny = by
        } else {
            nx = ax + t * dx
            ny = ay + t * dy
        }

        return sqrt(pow(px - nx, 2) + pow(py - ny, 2))
    }

    /// Find the closest point on the start line segment to the user's position
    static func closestPointOnLine(p: CLLocation, a: CLLocation, b: CLLocation) -> CLLocation {
        let scaleLat = Constants.metersPerDegreeLatitude
        let scaleLon = cos(p.coordinate.latitude * .pi / 180) * Constants.metersPerDegreeLatitude

        let px = p.coordinate.longitude * scaleLon
        let py = p.coordinate.latitude * scaleLat
        let ax = a.coordinate.longitude * scaleLon
        let ay = a.coordinate.latitude * scaleLat
        let bx = b.coordinate.longitude * scaleLon
        let by = b.coordinate.latitude * scaleLat

        let dx = bx - ax
        let dy = by - ay

        if dx == 0 && dy == 0 { return a }

        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))

        let nx = ax + t * dx
        let ny = ay + t * dy

        // Convert back to lat/lon
        let lon = nx / scaleLon
        let lat = ny / scaleLat

        return CLLocation(latitude: lat, longitude: lon)
    }

    // MARK: - Laylines

    static func calculateIntersectionTime(boatPos: CLLocation, boatHeading: Double, boatSpeed: Double, markPos: CLLocation, laylineBearing: Double) -> Double {
        let dLat = markPos.coordinate.latitude - boatPos.coordinate.latitude
        let dLon = markPos.coordinate.longitude - boatPos.coordinate.longitude

        let metersPerLat = Constants.metersPerDegreeLatitude
        let metersPerLon = cos(boatPos.coordinate.latitude * .pi/180) * Constants.metersPerDegreeLatitude

        let Qx = dLon * metersPerLon
        let Qy = dLat * metersPerLat

        let d2r = Double.pi / 180.0
        let Vx = sin(boatHeading * d2r)
        let Vy = cos(boatHeading * d2r)

        let Wx = sin(laylineBearing * d2r)
        let Wy = cos(laylineBearing * d2r)

        let det = Vx * (-Wy) - Vy * (-Wx)

        if abs(det) < 0.001 { return 0 }

        let detT = Qx * (-Wy) - Qy * (-Wx)
        let t_meters = detT / det

        let speedMS = max(boatSpeed * Constants.knotsToMetersPerSecond, 0.1)

        return t_meters / speedMS
    }
}

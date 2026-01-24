import Foundation

struct Constants {
    // Conversions
    static let knotsToMetersPerSecond = 1.0 / 1.94384
    static let metersPerSecondToKnots = 1.94384
    static let metersPerDegreeLatitude = 111139.0

    // Config
    static let headingDampingFactor = 0.15
    static let timerInterval = 0.1
    static let markRoundingDistance = 30.48 // 100 feet in meters
}

import Foundation
import SwiftData
import CoreLocation

@Model
final class RoutePoint {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: Date
    var workout: Workout?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double, altitude: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
    }

    convenience init(from location: CLLocation) {
        self.init(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            timestamp: location.timestamp
        )
    }
}

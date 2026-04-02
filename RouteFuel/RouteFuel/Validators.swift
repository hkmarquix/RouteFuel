import Foundation

enum DestinationSearchValidator {
    static func filterSelectableResults(_ items: [RawDestinationSearchItem]) -> [DestinationSearchResult] {
        items.compactMap { item in
            guard
                let label = item.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                !label.isEmpty,
                let latitude = item.latitude,
                (-90.0 ... 90.0).contains(latitude),
                let longitude = item.longitude,
                (-180.0 ... 180.0).contains(longitude),
                let countryCode = item.countryCode,
                countryCode == "GB"
            else {
                return nil
            }

            return DestinationSearchResult(
                id: UUID(),
                label: label,
                coordinate: Coordinate(lat: latitude, lng: longitude),
                countryCode: countryCode
            )
        }
    }
}

enum GoogleMapsDeepLinkBuilder {
    static func url(waypoint: Coordinate, destination: Coordinate) -> URL? {
        var components = URLComponents()
        components.scheme = "comgooglemaps"
        components.host = ""
        components.percentEncodedQuery = [
            "saddr=Current%20Location",
            "daddr=\(waypoint.googleMapsValue)+to:\(destination.googleMapsValue)",
            "directionsmode=driving"
        ].joined(separator: "&")
        return components.url
    }

    static func webURL(waypoint: Coordinate, destination: Coordinate) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/maps/dir/"
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: "Current Location"),
            URLQueryItem(name: "destination", value: destination.googleMapsValue),
            URLQueryItem(name: "waypoints", value: waypoint.googleMapsValue),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        return components.url
    }
}

enum PolylineCodec {
    static func decode(_ polyline: String) -> [Coordinate]? {
        guard !polyline.isEmpty else { return nil }

        var coordinates: [Coordinate] = []
        var index = polyline.startIndex
        var latitude = 0
        var longitude = 0

        while index < polyline.endIndex {
            guard let latitudeDelta = decodeComponent(polyline, index: &index),
                  let longitudeDelta = decodeComponent(polyline, index: &index)
            else {
                return nil
            }

            latitude += latitudeDelta
            longitude += longitudeDelta

            let coordinate = Coordinate(
                lat: Double(latitude) / 100_000,
                lng: Double(longitude) / 100_000
            )

            guard (-90.0 ... 90.0).contains(coordinate.lat),
                  (-180.0 ... 180.0).contains(coordinate.lng) else {
                return nil
            }

            coordinates.append(coordinate)
        }

        return coordinates.count >= 2 ? coordinates : nil
    }

    static func encode(_ coordinates: [Coordinate]) -> String {
        var result = ""
        var lastLat = 0
        var lastLng = 0

        for coordinate in coordinates {
            let lat = Int(round(coordinate.lat * 100_000))
            let lng = Int(round(coordinate.lng * 100_000))

            result += encodeComponent(lat - lastLat)
            result += encodeComponent(lng - lastLng)

            lastLat = lat
            lastLng = lng
        }

        return result
    }

    private static func decodeComponent(_ polyline: String, index: inout String.Index) -> Int? {
        var result = 0
        var shift = 0

        while index < polyline.endIndex {
            let value = Int(polyline[index].asciiValue ?? 0) - 63
            guard value >= 0 else { return nil }
            index = polyline.index(after: index)

            result |= (value & 0x1F) << shift
            shift += 5

            if value < 0x20 {
                let delta = (result & 1) == 0 ? (result >> 1) : ~(result >> 1)
                return delta
            }
        }

        return nil
    }

    private static func encodeComponent(_ value: Int) -> String {
        var chunk = value < 0 ? ~(value << 1) : value << 1
        var output = ""

        while chunk >= 0x20 {
            output.append(Character(UnicodeScalar((0x20 | (chunk & 0x1F)) + 63)!))
            chunk >>= 5
        }

        output.append(Character(UnicodeScalar(chunk + 63)!))
        return output
    }
}

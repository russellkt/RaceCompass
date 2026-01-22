import Foundation

class GPXParser: NSObject, XMLParserDelegate {
    private var waypoints: [Waypoint] = []
    private var currentElement: String = ""
    private var currentName: String = ""
    private var currentLat: Double?
    private var currentLon: Double?

    func parse(data: Data) -> [Waypoint] {
        waypoints = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return waypoints
    }

    func parse(url: URL) -> [Waypoint]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        if elementName == "wpt" {
            currentName = ""
            if let latStr = attributeDict["lat"], let lat = Double(latStr) {
                currentLat = lat
            }
            if let lonStr = attributeDict["lon"], let lon = Double(lonStr) {
                currentLon = lon
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentElement == "name" && !trimmed.isEmpty {
            currentName += trimmed
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "wpt" {
            if let lat = currentLat, let lon = currentLon {
                let name = currentName.isEmpty ? "Waypoint" : currentName
                let waypoint = Waypoint(name: name, latitude: lat, longitude: lon)
                waypoints.append(waypoint)
            }
            currentLat = nil
            currentLon = nil
            currentName = ""
        }
        currentElement = ""
    }
}

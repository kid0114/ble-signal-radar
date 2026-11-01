import Foundation

struct BLEAdvertisement {
    let identifier: UUID
    let name: String?
    let rssi: Int
    let manufacturerData: Data?

    var manufacturer: String? {
        guard let data = manufacturerData, data.count >= 2 else { return nil }
        let bytes = Array(data.prefix(2))
        return String(format: "0x%04X", Int(bytes[0]) | (Int(bytes[1]) << 8))
    }

    func nearbyPeripheral(at date: Date) -> NearbyPeripheral {
        NearbyPeripheral(identifier: identifier, name: name, rssi: rssi,
                         lastSeen: date, manufacturer: manufacturer)
    }
}

struct NearbyPeripheral {
    let identifier: UUID
    var name: String?
    var rssi: Int
    var lastSeen: Date
    var manufacturer: String?

    func isFresh(at now: Date) -> Bool {
        validRSSI(rssi) && (0 ... 5).contains(now.timeIntervalSince(lastSeen))
    }

    // Discovery rows never inherit the selected target's propagation reference.
    func uncalibratedDistanceText(at now: Date) -> String? {
        guard isFresh(at: now) else { return nil }
        return DistanceParameters().estimateText(rssi: Double(rssi))
    }
}

enum BLEScannerState {
    case initialising, poweredOn, poweredOff, unauthorized, unsupported, resetting, unknown
}

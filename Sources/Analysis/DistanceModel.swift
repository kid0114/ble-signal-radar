import Foundation

struct DistanceParameters: Codable {
    // BLE-oriented propagation assumptions, not instrument calibration or universal RF ranging.
    var referenceRSSI: Double = -59
    var pathLossExponent: Double = 2.5
    var referenceCalibrated: Bool = false

    var isValid: Bool {
        referenceRSSI.isFinite && (-126 ... -1).contains(referenceRSSI) &&
        pathLossExponent.isFinite && (1 ... 6).contains(pathLossExponent)
    }

    func estimatedMeters(rssi: Double) -> Double? {
        guard isValid, rssi.isFinite, rssi > -127, rssi < 0 else { return nil }
        let value = pow(10, (referenceRSSI - rssi) / (10 * pathLossExponent))
        return value.isFinite ? value : nil
    }

    func estimateText(rssi: Double) -> String? {
        guard let meters = estimatedMeters(rssi: rssi) else { return nil }
        if meters < 0.1 { return "<0.1" }
        return String(format: meters >= 1000 ? "%.1g" : (meters < 10 ? "%.1f" : "%.0f"), meters)
    }
}

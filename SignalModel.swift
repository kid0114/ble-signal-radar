import Foundation

// Parse a user-configured 0x07 snapshot, NOT an authenticated identifier.
// The mutable 0x12 status frame is deliberately not part of the match.
func matchesHistoricalPayload(_ data: Data, prefix: [UInt8]) -> Bool {
    let bytes = Array(data)
    guard !prefix.isEmpty, bytes.count >= 2, bytes[0] == 0x4c, bytes[1] == 0x00 else { return false }
    var index = 2
    while index + 2 <= bytes.count {
        let type = bytes[index], length = Int(bytes[index + 1])
        let start = index + 2, end = start + length
        guard end <= bytes.count else { return false }
        if type == 0x07, length >= prefix.count,
           bytes[start..<(start + prefix.count)].elementsEqual(prefix) {
            return true
        }
        index = end
    }
    return false
}

func validRSSI(_ value: Int) -> Bool { value > -127 && value < 0 }

func capture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range])
}

struct TargetEvent {
    let date: Date
    let rssi: Int
    let advertisementStamp: String
}

private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    return formatter
}()

// Accept only the target accessory's found events, with an advertisement timestamp.
// RSSI statistics for other connections and scan filter thresholds are not samples.
func parseTargetEvent(_ data: Data, caseID: String) -> TargetEvent? {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = object["eventMessage"] as? String,
          message.hasPrefix("Accessory found: CBAccessoryInfo: ID \(caseID),"),
          let number = capture(#"\bRSSI (-?\d+)(?:,|$)"#, in: message),
          let rssi = Int(number), validRSSI(rssi),
          let stamp = capture(#"AdTsMC <(\d+)>"#, in: message),
          let timestamp = object["timestamp"] as? String,
          let date = logDateFormatter.date(from: timestamp) else { return nil }
    return TargetEvent(date: date, rssi: rssi, advertisementStamp: stamp)
}

enum SignalSource { case systemIdentifier, historicalPayload, selectedPeripheral }

struct SignalSample {
    let date: Date
    let rssi: Int
    let source: SignalSource
}

final class SignalHistory {
    private(set) var samples: [SignalSample] = []
    private var stamps = Set<String>()
    private var stampOrder: [String] = []
    let startedAt: Date

    init(startedAt: Date = Date()) { self.startedAt = startedAt }

    @discardableResult
    func accept(_ event: TargetEvent, now: Date = Date()) -> Bool {
        guard event.date >= startedAt, event.date <= now.addingTimeInterval(2),
              !stamps.contains(event.advertisementStamp) else { return false }
        stamps.insert(event.advertisementStamp)
        stampOrder.append(event.advertisementStamp)
        if stampOrder.count > 2048 { stamps.remove(stampOrder.removeFirst()) }
        append(SignalSample(date: event.date, rssi: event.rssi, source: .systemIdentifier))
        return true
    }

    func append(_ sample: SignalSample) {
        guard validRSSI(sample.rssi) else { return }
        let index = samples.firstIndex(where: { $0.date > sample.date }) ?? samples.endIndex
        samples.insert(sample, at: index)
        if samples.count > 4096 { samples.removeFirst(samples.count - 4096) }
    }

    var latest: SignalSample? { samples.last }
    func isFresh(at now: Date) -> Bool {
        guard let sample = latest else { return false }
        return (-2 ... 5).contains(now.timeIntervalSince(sample.date))
    }

    // Use only recent samples from the latest source; never carry old RSSI into a distance.
    func recentRSSI(at now: Date) -> [Double] {
        guard isFresh(at: now), let latest else { return [] }
        return Array(samples.reversed().filter {
            $0.source == latest.source && (0 ... 10).contains(now.timeIntervalSince($0.date))
        }.prefix(9)).map { Double($0.rssi) }
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

    // Discovery rows have no per-device calibration. Never reuse the selected
    // target's calibrated reference for unrelated nearby devices.
    func uncalibratedDistanceText(at now: Date) -> String? {
        guard isFresh(at: now) else { return nil }
        return DistanceParameters().estimateText(rssi: Double(rssi))
    }
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty, values.allSatisfy({ $0.isFinite }) else { return nil }
    let sorted = values.sorted(), middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

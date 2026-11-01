import Foundation

// A historical 0x07 snapshot is a candidate match, never authenticated identity.
// The mutable 0x12 status frame is deliberately excluded.
func matchesHistoricalPayload(_ data: Data, prefix: [UInt8]) -> Bool {
    let bytes = Array(data)
    guard !prefix.isEmpty, bytes.count >= 2, bytes[0] == 0x4c, bytes[1] == 0x00 else { return false }
    var index = 2
    while index + 2 <= bytes.count {
        let type = bytes[index], length = Int(bytes[index + 1])
        let start = index + 2, end = start + length
        guard end <= bytes.count else { return false }
        if type == 0x07, length >= prefix.count,
           bytes[start..<(start + prefix.count)].elementsEqual(prefix) { return true }
        index = end
    }
    return false
}

private func capture(_ pattern: String, in text: String) -> String? {
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

// Backend-specific deduplication does not belong in generic signal history.
final class AirPodsEventFilter {
    let startedAt: Date
    private var stamps = Set<String>()
    private var stampOrder: [String] = []

    init(startedAt: Date) { self.startedAt = startedAt }

    func accepts(_ event: TargetEvent, now: Date = Date()) -> Bool {
        guard validRSSI(event.rssi), event.date >= startedAt,
              event.date <= now.addingTimeInterval(2),
              !stamps.contains(event.advertisementStamp) else { return false }
        stamps.insert(event.advertisementStamp)
        stampOrder.append(event.advertisementStamp)
        if stampOrder.count > 2048 { stamps.remove(stampOrder.removeFirst()) }
        return true
    }
}

enum AirPodsLogRecord {
    case event(TargetEvent)
    case diagnostic(String)
}

// Pure, bounded NDJSON framing; separately testable without launching /usr/bin/log.
final class AirPodsLogDecoder {
    private let identifier: String
    private let bufferLimit: Int
    private var buffer = Data()
    var bufferedByteCount: Int { buffer.count }

    init(identifier: String, bufferLimit: Int = 1_048_576) {
        self.identifier = identifier
        self.bufferLimit = bufferLimit
    }

    func consume(_ data: Data) -> [AirPodsLogRecord] {
        buffer.append(data)
        var records: [AirPodsLogRecord] = []
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            if let event = parseTargetEvent(line, caseID: identifier) {
                records.append(.event(event))
            } else if let text = String(data: line, encoding: .utf8), text.hasPrefix("log:") {
                records.append(.diagnostic(String(text.prefix(100))))
            }
        }
        if buffer.count > bufferLimit { buffer.removeAll() }
        return records
    }
}

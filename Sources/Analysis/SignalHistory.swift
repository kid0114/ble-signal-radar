import Foundation

// This range is for the existing BLE RSSI workflow, not arbitrary RF power measurements.
func validRSSI(_ value: Int) -> Bool { value > -127 && value < 0 }

enum SignalSource { case systemIdentifier, historicalPayload, selectedPeripheral }

// A narrow RSSI projection for the current UI, not the universal observation format.
struct SignalSample {
    let date: Date
    let rssi: Int
    let source: SignalSource
}

final class SignalHistory {
    private(set) var samples: [SignalSample] = []
    let startedAt: Date

    init(startedAt: Date = Date()) { self.startedAt = startedAt }

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

    func recentRSSI(at now: Date) -> [Double] {
        guard isFresh(at: now), let latest else { return [] }
        return Array(samples.reversed().filter {
            $0.source == latest.source && (0 ... 10).contains(now.timeIntervalSince($0.date))
        }.prefix(9)).map { Double($0.rssi) }
    }
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty, values.allSatisfy({ $0.isFinite }) else { return nil }
    let sorted = values.sorted(), middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

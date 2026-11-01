import Foundation

@main
struct Tests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            count += 1
        }
        func rejects(_ name: String, _ operation: () throws -> Void) {
            do { try operation(); fatalError("FAIL: \(name)") }
            catch { count += 1 }
        }
        func hex(_ value: String) -> Data {
            Data(value.split(separator: " ").map { UInt8($0, radix: 16)! })
        }
        // Fictional identifiers and payloads only; never publish a user's device fingerprint.
        let caseID = "11111111-2222-3333-4444-555555555555"
        let prefix = Array(hex("06 15 20 aa bb cc dd ee ff"))
        let payload = "07 11 06 15 20 aa bb cc dd ee ff 00 00 00 00 01 02 03 00"
        func matches(_ data: Data) -> Bool { matchesHistoricalPayload(data, prefix: prefix) }
        check(matches(hex("4c 00 12 02 ae 02 " + payload)), "old status matches")
        check(matches(hex("4c 00 12 02 ae 00 " + payload)), "changed status matches")
        check(matches(hex("4c 00 " + payload)), "no status frame")
        check(!matches(hex("4c 00 07 11 06 15")), "truncated frame rejected")
        check(!matches(hex("00 00 " + payload)), "other manufacturer rejected")
        check(!matches(hex("4c 00 10 02 ae 00")), "other Apple device rejected")
        check(!matches(Data()), "empty data safe")
        check(!matchesHistoricalPayload(hex("4c 00 " + payload), prefix: []), "empty configuration cannot match all Apple devices")
        var scannedDevice = NearbyPeripheral(identifier: UUID(), name: "Generic BLE sensor", rssi: -46,
            lastSeen: Date(timeIntervalSince1970: 1000), manufacturer: "0x1234")
        let observedAt = scannedDevice.lastSeen
        check(scannedDevice.uncalibratedDistanceText(at: observedAt) == "0.3", "discovery estimates do not require AirPods or Apple manufacturer data")
        check(scannedDevice.isFresh(at: observedAt.addingTimeInterval(5)), "discovery sample fresh at five-second boundary")
        check(scannedDevice.uncalibratedDistanceText(at: observedAt.addingTimeInterval(5.001)) == nil, "stale discovery distance hidden")
        check(!scannedDevice.isFresh(at: observedAt.addingTimeInterval(-1)), "future-dated discovery sample rejected")
        scannedDevice.rssi = 127
        check(scannedDevice.uncalibratedDistanceText(at: observedAt) == nil, "invalid discovery RSSI rejected")
        scannedDevice.rssi = -70
        scannedDevice.name = nil
        scannedDevice.manufacturer = nil
        check(scannedDevice.uncalibratedDistanceText(at: observedAt) == "2.8", "unnamed devices can have an uncalibrated model estimate")
        let unrelatedCalibration = DistanceParameters(referenceRSSI: -70, pathLossExponent: 2, referenceCalibrated: true)
        check(unrelatedCalibration.estimateText(rssi: -70) == "1.0" && scannedDevice.uncalibratedDistanceText(at: observedAt) == "2.8", "discovery rows never inherit another target's calibration")
        check(!validRSSI(127) && !validRSSI(-127) && !validRSSI(0) && validRSSI(-98), "RSSI sentinels")

        let timestamp = "2026-01-01 12:00:00.323000-0700"
        let message = "Accessory found: CBAccessoryInfo: ID \(caseID), device: CBDevice <private>, RSSI -61, Ch 39, AdTsMC <123456789>"
        func record(_ message: String, time: String = timestamp) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["timestamp": time, "eventMessage": message])
        }
        func parse(_ data: Data) -> TargetEvent? { parseTargetEvent(data, caseID: caseID) }
        let event = parse(try record(message))!
        check(event.rssi == -61 && event.advertisementStamp == "123456789", "target event parsed")
        let expected = ISO8601DateFormatter().date(from: "2026-01-01T19:00:00Z")!
        check(abs(event.date.timeIntervalSince(expected) - 0.323) < 0.002, "timestamp and timezone parsed")
        check(parse(try record(message.replacingOccurrences(of: caseID, with: "OTHER"))) == nil, "other ID rejected")
        check(parse(try record(message.replacingOccurrences(of: "Accessory found:", with: "Accessory lost:"))) == nil, "lost is not a sample")
        check(parse(try record("Le [0x401]: rssi -47")) == nil, "unrelated connection ignored")
        check(parse(try record(message.replacingOccurrences(of: "RSSI -61", with: "RSSI 127"))) == nil, "invalid log RSSI ignored")
        check(parse(try record(message, time: "invalid")) == nil, "invalid time rejected")
        let history = SignalHistory(startedAt: event.date.addingTimeInterval(-1))
        let filter = AirPodsEventFilter(startedAt: history.startedAt)
        func accept(_ event: TargetEvent, now: Date) -> Bool {
            guard filter.accepts(event, now: now) else { return false }
            history.append(SignalSample(date: event.date, rssi: event.rssi, source: .systemIdentifier))
            return true
        }
        check(accept(event, now: event.date), "new event accepted")
        check(!accept(event, now: event.date.addingTimeInterval(1)), "repeated AdTsMC ignored")
        check(history.isFresh(at: event.date.addingTimeInterval(4)), "fresh window")
        check(!history.isFresh(at: event.date.addingTimeInterval(6)), "sample goes stale without new data")
        check(history.recentRSSI(at: event.date.addingTimeInterval(6)).isEmpty, "stale sample cannot drive distance estimates")
        check(history.samples.count == 1, "UI ticks do not fabricate samples")
        let laterFilter = AirPodsEventFilter(startedAt: event.date.addingTimeInterval(10))
        check(!laterFilter.accepts(event, now: event.date.addingTimeInterval(20)), "historical replay rejected")
        let next = TargetEvent(date: event.date.addingTimeInterval(2), rssi: -70, advertisementStamp: "123456790")
        check(accept(next, now: next.date), "changed advertisement timestamp accepted")
        let delayed = TargetEvent(date: event.date.addingTimeInterval(1), rssi: -65, advertisementStamp: "123456791")
        check(accept(delayed, now: next.date), "delayed target event accepted alongside newer callback")
        check(history.latest?.rssi == -70, "delayed event cannot overwrite latest genuine value")
        history.append(SignalSample(date: next.date.addingTimeInterval(1), rssi: -50, source: .historicalPayload))
        check(history.recentRSSI(at: next.date.addingTimeInterval(1)) == [-50], "different sources not mixed in median")
        for i in 0..<15 {
            history.append(SignalSample(date: next.date.addingTimeInterval(2 + Double(i) / 10), rssi: -60, source: .historicalPayload))
        }
        check(history.recentRSSI(at: next.date.addingTimeInterval(4)).count == 9, "recent smoothing window limited to nine actual samples")

        let model = DistanceParameters(referenceRSSI: -60, pathLossExponent: 2, referenceCalibrated: false)
        check(abs(model.estimatedMeters(rssi: -60)! - 1) < 1e-9, "reference RSSI corresponds to 1 m in model")
        check(abs(model.estimatedMeters(rssi: -80)! - 10) < 1e-9, "20 dB loss at n=2 corresponds to factor ten")
        check(model.estimatedMeters(rssi: -50)! < model.estimatedMeters(rssi: -70)!, "weaker RSSI produces larger model distance")
        check(model.estimatedMeters(rssi: 127) == nil && model.estimatedMeters(rssi: -.infinity) == nil, "invalid RSSI has no model distance")
        check(DistanceParameters(referenceRSSI: -59, pathLossExponent: 0).estimatedMeters(rssi: -60) == nil, "zero exponent rejected")
        check(!DistanceParameters(referenceRSSI: .nan).isValid, "NaN reference rejected")
        check(!DistanceParameters().referenceCalibrated, "defaults explicitly uncalibrated")
        check(abs(DistanceParameters().estimatedMeters(rssi: -46)! - 0.3019951720) < 1e-9, "minus 46 dBm maps to about 0.302 m under default assumptions")
        check(DistanceParameters().estimateText(rssi: -46) == "0.3", "last-sample estimate formatted in metres")
        check(DistanceParameters().estimateText(rssi: 127) == nil, "unavailable RSSI has no formatted distance")
        check(DistanceParameters().estimateText(rssi: -10) == "<0.1", "very small estimate is not rounded to zero metres")
        let staleHistory = SignalHistory(startedAt: event.date)
        staleHistory.append(SignalSample(date: event.date, rssi: -46, source: .systemIdentifier))
        check(staleHistory.recentRSSI(at: event.date.addingTimeInterval(30)).isEmpty, "historical reference does not revive current estimate")
        check(DistanceParameters().estimateText(rssi: Double(staleHistory.latest!.rssi)) == "0.3", "last raw sample remains available as a historical model reference")
        check(median([-60, -61, -59, -120, -62]) == -61, "median resists a single extreme sample")
        check(median([-60, -62]) == -61 && median([]) == nil, "even and empty median")
        check(median([.nan]) == nil, "invalid median rejected")

        var config = MeterConfiguration()
        check(config.caseIdentifier == nil && config.payloadBytes.isEmpty, "no private target compiled into application")
        config.caseIdentifier = caseID
        config.accessoryPayloadPrefix = "06 15 20 aa bb cc dd ee ff"
        config.language = .chinese
        try config.validate()
        check(config.payloadBytes == prefix, "configuration fingerprint decoded")
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("signal-radar-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temp) }
        try config.save(to: temp)
        let restored = try MeterConfiguration.load(from: temp)
        check(restored.caseIdentifier == caseID && restored.language == .chinese, "configuration and Chinese preference round-trip")
        config.language = .english
        config.distance.referenceRSSI = -64
        config.distance.referenceCalibrated = true
        try config.save(to: temp)
        let english = try MeterConfiguration.load(from: temp)
        check(english.language == .english && english.distance.referenceRSSI == -64 && english.distance.referenceCalibrated, "English and reference calibration round-trip")
        config.caseIdentifier = "injected predicate"
        rejects("invalid UUID rejected") { try config.validate() }
        config.caseIdentifier = caseID
        config.accessoryPayloadPrefix = "06 xx"
        rejects("invalid hex prefix rejected") { try config.validate() }
        config.accessoryPayloadPrefix = nil
        config.distance.pathLossExponent = .infinity
        rejects("non-finite model rejected") { try config.validate() }
        let minimal = try JSONDecoder().decode(MeterConfiguration.self, from: Data("{}".utf8))
        check(minimal.caseIdentifier == nil && minimal.distance.referenceRSSI == -59, "minimal configuration has safe defaults")
        check(minimal.showDiscoveryDistances, "old configurations receive default-enabled discovery-distance option")
        var distanceOption = MeterConfiguration()
        distanceOption.showDiscoveryDistances = false
        try distanceOption.save(to: temp)
        let optionReloaded = try MeterConfiguration.load(from: temp)
        check(!optionReloaded.showDiscoveryDistances, "discovery-distance toggle persists")
        check(!ConfigurationError.invalidDistance.message(in: .chinese).isEmpty && ConfigurationError.invalidDistance.message(in: .english).contains("reference"), "validation errors bilingual")
        var generic = MeterConfiguration()
        generic.peripheralIdentifier = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        try generic.save(to: temp)
        let genericReloaded = try MeterConfiguration.load(from: temp)
        check(genericReloaded.peripheralIdentifier == generic.peripheralIdentifier && genericReloaded.caseIdentifier == nil, "generic BLE target can be persisted without AirPods configuration")
        generic.peripheralIdentifier = "not-a-uuid"
        rejects("generic target identifier validated") { try generic.validate() }
        let genericHistory = SignalHistory(startedAt: event.date)
        genericHistory.append(SignalSample(date: event.date, rssi: -57, source: .selectedPeripheral))
        check(genericHistory.recentRSSI(at: event.date.addingTimeInterval(1)) == [-57], "generic source feeds distance median")
        genericHistory.append(SignalSample(date: event.date.addingTimeInterval(1), rssi: -90, source: .systemIdentifier))
        check(genericHistory.recentRSSI(at: event.date.addingTimeInterval(1)) == [-90], "generic and accessory sources never mixed")
        try checkBackendFoundation(check)
        checkTrackingTarget(check)
        print("PASS: \(count) checks")
    }
}

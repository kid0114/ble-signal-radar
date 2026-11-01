import Foundation

// Synthetic fixtures remain in this command-line test process, never the live GUI.
private final class FixtureBackend: SensorBackend {
    let descriptor = SensorDescriptor(id: "test.receiver", name: "Synthetic test fixture",
                                      measurementKinds: [.bleAdvertisement])
    var onObservation: ((Observation<BLEAdvertisement>) -> Void)?
    private(set) var running = false
    private let observation: Observation<BLEAdvertisement>

    init(_ observation: Observation<BLEAdvertisement>) { self.observation = observation }
    func start() {
        guard !running else { return }
        running = true
        onObservation?(observation)
    }
    func stop() { running = false }
}

func checkBackendFoundation(_ check: (Bool, String) -> Void) throws {
    let time = Date(timeIntervalSince1970: 1_700_000_000)
    let sessionID = UUID()
    let context = ObservationContext(sessionID: sessionID, receiverID: "test.receiver",
        observedAt: time, receivedAt: time.addingTimeInterval(0.4),
        timeBasis: .receiverCallback, provenance: .synthetic)
    check(context.observedAt != context.receivedAt, "capture and arrival times remain distinct")
    check(context.provenance == .synthetic, "synthetic provenance is explicit")
    let restored = try JSONDecoder().decode(ObservationContext.self,
        from: JSONEncoder().encode(context))
    check(restored == context, "observation metadata round-trips without losing provenance")
    let nextContext = ObservationContext(sessionID: sessionID, receiverID: "test.receiver",
        observedAt: time, receivedAt: time, timeBasis: .systemEvent, provenance: .replay)
    check(nextContext.id != context.id, "each observation has its own identity")
    check(nextContext.sessionID == context.sessionID, "observations can share an acquisition session")
    check(nextContext.timeBasis == .systemEvent && nextContext.provenance == .replay,
          "replay and system-event timing are not disguised as live capture")

    let advertisement = BLEAdvertisement(identifier: UUID(), name: "Fixture", rssi: -60,
        manufacturerData: Data([0x34, 0x12, 0xaa]))
    check(advertisement.manufacturer == "0x1234", "manufacturer code remains little-endian")
    let nearby = advertisement.nearbyPeripheral(at: time)
    check(nearby.identifier == advertisement.identifier && nearby.lastSeen == time,
          "discovery projection preserves identity and observation time")
    check(nearby.rssi == -60 && nearby.name == "Fixture", "discovery projection preserves reported fields")
    let shortAdvertisement = BLEAdvertisement(identifier: UUID(), name: nil, rssi: -70,
        manufacturerData: Data([0x4c]))
    check(shortAdvertisement.manufacturer == nil, "truncated manufacturer data has no company code")
    check(shortAdvertisement.nearbyPeripheral(at: time).name == nil, "missing name remains unknown")

    let observation = Observation(context: context, payload: advertisement)
    let backend = FixtureBackend(observation)
    var received: [Observation<BLEAdvertisement>] = []
    backend.onObservation = { received.append($0) }
    backend.start()
    backend.start()
    check(backend.running && received.count == 1, "typed backend contract supports idempotent fixture start")
    check(received.first?.context == context && received.first?.payload.rssi == -60,
          "typed delivery preserves payload and metadata together")
    check(backend.descriptor.measurementKinds == [.bleAdvertisement], "capability describes the implemented measurement kind")
    backend.stop()
    backend.stop()
    check(!backend.running, "fixture stop is idempotent")

    let caseID = "11111111-2222-3333-4444-555555555555"
    let line = try JSONSerialization.data(withJSONObject: [
        "timestamp": "2026-01-01 12:00:00.323000-0700",
        "eventMessage": "Accessory found: CBAccessoryInfo: ID \(caseID), RSSI -61, AdTsMC <123>"
    ])
    let decoder = AirPodsLogDecoder(identifier: caseID)
    let midpoint = line.count / 2
    check(decoder.consume(Data(line.prefix(midpoint))).isEmpty, "partial NDJSON does not fabricate an event")
    check(decoder.bufferedByteCount == midpoint, "partial NDJSON is buffered")
    let records = decoder.consume(Data(line.dropFirst(midpoint)) + Data([10]))
    check(records.count == 1, "split NDJSON produces exactly one record")
    if case .event(let event)? = records.first {
        check(event.rssi == -61 && event.advertisementStamp == "123", "split record preserves event fields")
    } else { check(false, "split record must be a parsed event") }
    check(decoder.bufferedByteCount == 0, "complete line leaves no stale bytes")
    let diagnostic = decoder.consume(Data("log: diagnostic\nnot JSON\n".utf8))
    check(diagnostic.count == 1, "invalid lines are ignored while diagnostics remain visible")
    if case .diagnostic(let text)? = diagnostic.first {
        check(text == "log: diagnostic", "diagnostics remain separate from observations")
    } else { check(false, "diagnostic must not become an observation") }
    check(decoder.consume(line + Data([10]) + line + Data([10])).count == 2,
          "framing retains both records before backend-specific deduplication")
    let wrongTarget = AirPodsLogDecoder(identifier: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
    check(wrongTarget.consume(line + Data([10])).isEmpty, "stream decoder rejects other configured targets")
    let bounded = AirPodsLogDecoder(identifier: caseID, bufferLimit: 16)
    check(bounded.consume(Data(repeating: 32, count: 17)).isEmpty && bounded.bufferedByteCount == 0,
          "unterminated log buffer is bounded")

    let filter = AirPodsEventFilter(startedAt: time)
    check(!filter.accepts(TargetEvent(date: time.addingTimeInterval(-1), rssi: -60,
        advertisementStamp: "old"), now: time), "filter rejects pre-session events")
    check(!filter.accepts(TargetEvent(date: time.addingTimeInterval(3), rssi: -60,
        advertisementStamp: "future"), now: time), "filter rejects excessive future clock skew")
    check(!filter.accepts(TargetEvent(date: time, rssi: 127,
        advertisementStamp: "invalid"), now: time), "filter rejects invalid RSSI before deduplication")
    check(filter.accepts(TargetEvent(date: time, rssi: -60,
        advertisementStamp: "invalid"), now: time), "rejected data does not consume a valid event stamp")
    check(!filter.accepts(TargetEvent(date: time, rssi: -60,
        advertisementStamp: "invalid"), now: time), "accepted event stamps are deduplicated")
    check(filter.accepts(TargetEvent(date: time.addingTimeInterval(2), rssi: -65,
        advertisementStamp: "boundary"), now: time), "existing two-second clock-skew tolerance is preserved")

    let invalidBackend = AirPodsLogBackend(identifier: "not-a-uuid", sessionID: sessionID, startedAt: time)
    var statusChanges = 0
    invalidBackend.onStatusChanged = { statusChanges += 1 }
    invalidBackend.start()
    check(!invalidBackend.isRunning && invalidBackend.failure != nil,
          "invalid backend configuration is rejected without spawning a log process")
    check(statusChanges == 1, "backend configuration failure emits status notification")
    invalidBackend.stop()
    invalidBackend.stop()
    check(!invalidBackend.isRunning, "stopping an unstarted log backend is safe")
}

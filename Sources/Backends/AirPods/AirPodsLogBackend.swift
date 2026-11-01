import Foundation

final class AirPodsLogBackend: SensorBackend {
    let descriptor = SensorDescriptor(id: "local.bluetoothd", name: "Optional AirPods system events",
                                      measurementKinds: [.accessorySystemEvent])
    var onObservation: ((Observation<TargetEvent>) -> Void)?
    var onStatusChanged: (() -> Void)?
    private(set) var failure: String?
    var isRunning: Bool { process?.isRunning == true }

    private let identifier: String
    private let sessionID: UUID
    private let filter: AirPodsEventFilter
    private var process: Process?
    private var pipe: Pipe?
    private var generation = UUID()

    init(identifier: String, sessionID: UUID, startedAt: Date) {
        self.identifier = identifier.uppercased()
        self.sessionID = sessionID
        self.filter = AirPodsEventFilter(startedAt: startedAt)
    }

    func start() {
        guard !isRunning else { return }
        stop()
        failure = nil
        guard UUID(uuidString: identifier) != nil else {
            failure = "Invalid accessory identifier"
            onStatusChanged?()
            return
        }
        let runID = UUID()
        generation = runID
        let decoder = AirPodsLogDecoder(identifier: identifier)
        let filter = self.filter // Preserve deduplication when restarting this session's stream.
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--level", "info", "--predicate",
            "process == \"bluetoothd\" AND eventMessage BEGINSWITH \"Accessory found: CBAccessoryInfo: ID \(identifier),\""]
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let receivedAt = Date()
            DispatchQueue.main.async {
                guard let self, self.generation == runID else { return }
                for record in decoder.consume(data) {
                    switch record {
                    case .event(let event):
                        guard filter.accepts(event, now: receivedAt) else { continue }
                        let context = ObservationContext(sessionID: self.sessionID,
                            receiverID: self.descriptor.id, observedAt: event.date,
                            receivedAt: receivedAt, timeBasis: .systemEvent, provenance: .live)
                        self.onObservation?(Observation(context: context, payload: event))
                    case .diagnostic(let message):
                        self.failure = message
                        self.onStatusChanged?()
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            DispatchQueue.main.async {
                guard let self, self.generation == runID else { return }
                self.failure = "exit \(code)"
                self.onStatusChanged?()
            }
        }
        self.process = process
        self.pipe = pipe
        do { try process.run() }
        catch {
            failure = error.localizedDescription
            pipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            onStatusChanged?()
        }
    }

    func stop() {
        // Invalidate already queued callbacks before ending this backend's own process.
        generation = UUID()
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        pipe = nil
    }

    deinit { stop() }
}

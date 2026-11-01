import Foundation

// Receiver IDs identify local collection channels, not authenticated hardware or targets.
enum ObservationTimeBasis: String, Codable {
    case receiverCallback, systemEvent
}

enum ObservationProvenance: String, Codable {
    case live, replay, synthetic
}

struct ObservationContext: Codable, Equatable {
    let id: UUID
    let sessionID: UUID
    let receiverID: String
    let observedAt: Date
    let receivedAt: Date
    let timeBasis: ObservationTimeBasis
    let provenance: ObservationProvenance

    init(id: UUID = UUID(), sessionID: UUID, receiverID: String,
         observedAt: Date, receivedAt: Date, timeBasis: ObservationTimeBasis,
         provenance: ObservationProvenance) {
        self.id = id
        self.sessionID = sessionID
        self.receiverID = receiverID
        self.observedAt = observedAt
        self.receivedAt = receivedAt
        self.timeBasis = timeBasis
        self.provenance = provenance
    }
}

// Payload types belong to their backends. Spectrum/IQ must not be flattened into RSSI.
struct Observation<Payload> {
    let context: ObservationContext
    let payload: Payload
}

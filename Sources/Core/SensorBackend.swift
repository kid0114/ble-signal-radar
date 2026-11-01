import Foundation

// Only measurement kinds actually supported today. Extend alongside real adapters.
enum MeasurementKind: String, Codable {
    case bleAdvertisement, accessorySystemEvent
}

struct SensorDescriptor: Equatable {
    let id: String
    let name: String
    let measurementKinds: Set<MeasurementKind>
}

// Current adapters deliver callbacks on the main queue. This is not a remote transport
// or a high-throughput IQ bus; future workers must define their own bounded data path.
protocol SensorBackend: AnyObject {
    associatedtype Payload
    var descriptor: SensorDescriptor { get }
    var onObservation: ((Observation<Payload>) -> Void)? { get set }
    func start()
    func stop()
}

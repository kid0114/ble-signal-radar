import CoreBluetooth
import Foundation

final class BLEScanner: NSObject, SensorBackend, CBCentralManagerDelegate {
    let descriptor = SensorDescriptor(id: "local.corebluetooth", name: "macOS CoreBluetooth",
                                      measurementKinds: [.bleAdvertisement])
    var onObservation: ((Observation<BLEAdvertisement>) -> Void)?
    var onStatusChanged: (() -> Void)?
    private(set) var state = BLEScannerState.initialising
    private(set) var callbacks = 0
    private(set) var nearby: [UUID: NearbyPeripheral] = [:]
    var identifierCount: Int { identifiers.count }

    private let sessionID: UUID
    private var central: CBCentralManager?
    private var identifiers = Set<UUID>()
    private var wantsScanning = false

    init(sessionID: UUID) {
        self.sessionID = sessionID
        super.init()
    }

    func start() {
        wantsScanning = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
        } else if state == .poweredOn {
            scan()
        }
    }

    func stop() {
        wantsScanning = false
        central?.stopScan()
    }

    func rescan() {
        if state == .poweredOn {
            central?.stopScan()
            wantsScanning = true
            scan()
        }
    }

    private func scan() {
        central?.scanForPeripherals(withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: state = .poweredOn
        case .poweredOff: state = .poweredOff
        case .unauthorized: state = .unauthorized
        case .unsupported: state = .unsupported
        case .resetting: state = .resetting
        default: state = .unknown
        }
        if state == .poweredOn && wantsScanning { scan() }
        onStatusChanged?()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard wantsScanning else { return }
        callbacks += 1
        identifiers.insert(peripheral.identifier)
        guard validRSSI(RSSI.intValue) else { return }
        let now = Date()
        let advertisement = BLEAdvertisement(identifier: peripheral.identifier,
            name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name,
            rssi: RSSI.intValue,
            manufacturerData: advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)
        nearby[advertisement.identifier] = advertisement.nearbyPeripheral(at: now)
        if nearby.count > 512 {
            let recent = nearby.values.sorted { $0.lastSeen > $1.lastSeen }.prefix(512)
            nearby = Dictionary(uniqueKeysWithValues: recent.map { ($0.identifier, $0) })
        }
        // macOS exposes a callback time here, not a hardware RF capture timestamp.
        let context = ObservationContext(sessionID: sessionID, receiverID: descriptor.id,
            observedAt: now, receivedAt: now, timeBasis: .receiverCallback, provenance: .live)
        onObservation?(Observation(context: context, payload: advertisement))
    }
}

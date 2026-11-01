import Foundation

func checkTrackingTarget(_ check: (Bool, String) -> Void) {
    let id = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    let otherID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    var configuration = MeterConfiguration()
    configuration.language = .english
    check(trackingTargetText(configuration: configuration, nearby: [:]).contains("No tracking target"),
          "header distinguishes no selection from no fresh signal")
    configuration.peripheralIdentifier = id.uuidString
    check(trackingTargetText(configuration: configuration, nearby: [:]).contains(id.uuidString),
          "selected identifier is displayed before discovery or after restart")
    var device = NearbyPeripheral(identifier: id, name: "Fixture sensor", rssi: -60,
        lastSeen: Date(timeIntervalSince1970: 1000), manufacturer: nil)
    let text = trackingTargetText(configuration: configuration, nearby: [id: device])
    check(text.contains("Fixture sensor") && text.contains(id.uuidString),
          "selected target header shows both device name and full identifier")
    check(!device.isFresh(at: Date()) && text.contains("Fixture sensor"),
          "stale reception does not hide the selected tracking identity")
    device.name = "  \n "
    check(!trackingTargetText(configuration: configuration, nearby: [id: device]).contains(" · "),
          "blank names fall back to the identifier without a dangling separator")
    device.name = "Other fixture"
    configuration.peripheralIdentifier = otherID.uuidString
    check(!trackingTargetText(configuration: configuration, nearby: [id: device]).contains("Other fixture"),
          "target switch never reuses another device's name")
    configuration.language = .chinese
    check(trackingTargetText(configuration: configuration, nearby: [:]).hasPrefix("追踪目标："),
          "target identity header supports Chinese")
    configuration.peripheralIdentifier = nil
    configuration.caseIdentifier = otherID.uuidString
    check(trackingTargetText(configuration: configuration, nearby: [:]).contains(otherID.uuidString),
          "optional accessory configuration displays its target identifier")
    configuration.caseIdentifier = nil
    configuration.accessoryPayloadPrefix = "06 15 20 aa"
    let candidate = trackingTargetText(configuration: configuration, nearby: [:])
    check(candidate.contains("身份未验证") && !candidate.contains("06 15 20 aa"),
          "fingerprint mode stays qualified and does not expose raw payload bytes")
    configuration.language = .english
    check(trackingTargetText(configuration: configuration, nearby: [:]).contains("identity unverified"),
          "English fingerprint header preserves identity qualification")
}

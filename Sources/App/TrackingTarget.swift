import Foundation

// Display identity, not evidence of current reception or authenticated ownership.
func trackingTargetText(configuration: MeterConfiguration, nearby: [UUID: NearbyPeripheral]) -> String {
    let chinese = configuration.language == .chinese
    if let identifier = configuration.peripheralIdentifier {
        let name = UUID(uuidString: identifier).flatMap { nearby[$0]?.name }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = name.flatMap { $0.isEmpty ? nil : $0 }.map { "\($0) · \(identifier)" } ?? identifier
        return (chinese ? "追踪目标：" : "Tracking target: ") + identity
    }
    if let identifier = configuration.caseIdentifier {
        return (chinese ? "配件配置目标 ID：" : "Accessory configuration ID: ") + identifier
    }
    if !configuration.payloadBytes.isEmpty {
        return chinese ? "追踪配置：历史配件指纹候选（身份未验证）" : "Tracking configuration: historical accessory payload (identity unverified)"
    }
    return chinese ? "尚未选择追踪目标 · 请点击“选择设备”" : "No tracking target · Choose device to begin"
}

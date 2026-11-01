import Foundation

enum AppLanguage: String, Codable {
    case chinese = "zh", english = "en"
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .chinese : .english
    }
}

struct DistanceParameters: Codable {
    // Defaults are assumptions, not measured AirPods specifications.
    var referenceRSSI: Double = -59
    var pathLossExponent: Double = 2.5
    var referenceCalibrated: Bool = false

    var isValid: Bool {
        referenceRSSI.isFinite && (-126 ... -1).contains(referenceRSSI) &&
        pathLossExponent.isFinite && (1 ... 6).contains(pathLossExponent)
    }

    func estimatedMeters(rssi: Double) -> Double? {
        guard isValid, rssi.isFinite, rssi > -127, rssi < 0 else { return nil }
        // Log-distance path loss: RSSI(d) = RSSI(1m) - 10*n*log10(d).
        let value = pow(10, (referenceRSSI - rssi) / (10 * pathLossExponent))
        return value.isFinite ? value : nil
    }

    func estimateText(rssi: Double) -> String? {
        guard let meters = estimatedMeters(rssi: rssi) else { return nil }
        if meters < 0.1 { return "<0.1" }
        return String(format: meters >= 1000 ? "%.1g" : (meters < 10 ? "%.1f" : "%.0f"), meters)
    }
}

struct MeterConfiguration: Codable {
    var caseIdentifier: String?
    var peripheralIdentifier: String?
    var accessoryPayloadPrefix: String?
    var distance = DistanceParameters()
    var language = AppLanguage.systemDefault
    var showDiscoveryDistances = true

    enum CodingKeys: String, CodingKey { case caseIdentifier, peripheralIdentifier, accessoryPayloadPrefix, distance, language, showDiscoveryDistances }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        caseIdentifier = try values.decodeIfPresent(String.self, forKey: .caseIdentifier)
        peripheralIdentifier = try values.decodeIfPresent(String.self, forKey: .peripheralIdentifier)
        accessoryPayloadPrefix = try values.decodeIfPresent(String.self, forKey: .accessoryPayloadPrefix)
        distance = try values.decodeIfPresent(DistanceParameters.self, forKey: .distance) ?? DistanceParameters()
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .systemDefault
        showDiscoveryDistances = try values.decodeIfPresent(Bool.self, forKey: .showDiscoveryDistances) ?? true
    }

    var payloadBytes: [UInt8] {
        guard let text = accessoryPayloadPrefix else { return [] }
        return text.split(whereSeparator: { $0.isWhitespace }).compactMap { UInt8($0, radix: 16) }
    }

    func validate() throws {
        if [caseIdentifier, peripheralIdentifier].compactMap({ $0 }).contains(where: { UUID(uuidString: $0) == nil }) {
            throw ConfigurationError.invalidIdentifier
        }
        if let text = accessoryPayloadPrefix {
            let parts = text.split(whereSeparator: { $0.isWhitespace })
            guard (4 ... 17).contains(parts.count),
                  parts.allSatisfy({ $0.count == 2 && UInt8($0, radix: 16) != nil }) else {
                throw ConfigurationError.invalidPayload
            }
        }
        guard distance.isValid else {
            throw ConfigurationError.invalidDistance
        }
    }

    static func load(from url: URL) throws -> MeterConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return MeterConfiguration() }
        let configuration = try JSONDecoder().decode(MeterConfiguration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    func save(to url: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

enum ConfigurationError: LocalizedError {
    case invalidIdentifier, invalidPayload, invalidDistance
    func message(in language: AppLanguage) -> String {
        switch self {
        case .invalidIdentifier:
            return language == .chinese ? "目标标识必须是 UUID，或删除该字段" : "Target identifiers must be UUIDs, or omit the fields."
        case .invalidPayload:
            return language == .chinese ? "指纹需为 4–17 个空格分隔的十六进制字节" : "The payload prefix must contain 4–17 space-separated hexadecimal bytes."
        case .invalidDistance:
            return language == .chinese ? "1 米参考 RSSI 需在 -126…-1；路径损耗系数 n 需在 1…6" : "1 m reference RSSI must be -126…-1; path-loss exponent n must be 1…6."
        }
    }
    var errorDescription: String? { message(in: .systemDefault) }
}

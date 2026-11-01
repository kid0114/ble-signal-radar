import Cocoa

final class SignalWindowController: NSObject {
    var window: NSWindow!
    private let sessionID = UUID()
    private lazy var scanner = BLEScanner(sessionID: sessionID)
    var timer: Timer?
    var configuration = MeterConfiguration()
    var configurationError: Error?
    var configurationURL: URL {
        if let path = ProcessInfo.processInfo.environment["SIGNAL_RADAR_CONFIG"] ?? ProcessInfo.processInfo.environment["AIRPODS_METER_CONFIG"] {
            return URL(fileURLWithPath: path)
        }
        return Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("config.local.json")
    }
    var history = SignalHistory()
    var devicePicker: DevicePicker?
    let chooseDeviceButton = NSButton()
    let targetLabel = NSTextField(labelWithString: "")
    let graph = GraphView()
    let bigLabel = NSTextField(labelWithString: "--")
    let bigDistanceLabel = NSTextField(labelWithString: "--")
    let rssiHeading = NSTextField(labelWithString: "")
    let distanceHeading = NSTextField(labelWithString: "")
    let statusLabel = NSTextField(labelWithString: "")
    let distanceLabel = NSTextField(labelWithString: "")
    let parameterLabel = NSTextField(labelWithString: "")
    let warningLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")
    let lastEstimateLabel = NSTextField(labelWithString: "")
    let scanLabel = NSTextField(labelWithString: "")
    let logLabel = NSTextField(labelWithString: "")
    let countLabel = NSTextField(labelWithString: "")
    let referenceCaption = NSTextField(labelWithString: "")
    let exponentCaption = NSTextField(labelWithString: "")
    let calibrationLabel = NSTextField(labelWithString: "")
    let noteLabel = NSTextField(labelWithString: "")
    let identityLabel = NSTextField(labelWithString: "")
    let languagePopup = NSPopUpButton()
    let referenceField = NSTextField(string: "-59")
    let exponentField = NSTextField(string: "2.5")
    let applyButton = NSButton()
    let calibrateButton = NSButton()
    let rescanButton = NSButton()
    var coreMatches = 0
    var systemMatches = 0
    private var logBackend: AirPodsLogBackend?
    private var logFailure: String? { logBackend?.failure }
    let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    func t(_ chinese: String, _ english: String) -> String {
        configuration.language == .chinese ? chinese : english
    }

    func show() {
        do { configuration = try MeterConfiguration.load(from: configurationURL) }
        catch { configurationError = error }
        let menu = NSMenu(), item = NSMenuItem(), submenu = NSMenu()
        menu.addItem(item)
        submenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu
        NSApp.mainMenu = menu
        let addedBottomPadding: CGFloat = 12
        let targetHeaderHeight: CGFloat = 32
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 674 + addedBottomPadding + targetHeaderHeight),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        let content = window.contentView!
        func label(_ field: NSTextField, y: CGFloat, height: CGFloat = 20, size: CGFloat = 12) {
            field.frame = NSRect(x: 12, y: y, width: 736, height: height)
            field.font = .systemFont(ofSize: size)
            field.alignment = .center
            content.addSubview(field)
        }
        languagePopup.addItems(withTitles: ["中文", "English"])
        languagePopup.selectItem(at: configuration.language == .chinese ? 0 : 1)
        languagePopup.target = self
        languagePopup.action = #selector(changeLanguage)
        languagePopup.frame = NSRect(x: 630, y: 635, width: 112, height: 28)
        languagePopup.setAccessibilityLabel("Language / 语言")
        content.addSubview(languagePopup)
        label(rssiHeading, y: 635, size: 12)
        rssiHeading.frame = NSRect(x: 16, y: 635, width: 356, height: 20)
        rssiHeading.textColor = .secondaryLabelColor
        label(distanceHeading, y: 635, size: 12)
        distanceHeading.frame = NSRect(x: 388, y: 635, width: 224, height: 20)
        distanceHeading.textColor = .secondaryLabelColor
        for (field, x) in [(bigLabel, CGFloat(16)), (bigDistanceLabel, CGFloat(388))] {
            label(field, y: 565, height: 64, size: 46)
            field.frame = NSRect(x: x, y: 565, width: 356, height: 64)
            field.font = .monospacedDigitSystemFont(ofSize: 46, weight: .bold)
        }
        let separator = NSBox(frame: NSRect(x: 379, y: 566, width: 1, height: 64))
        separator.boxType = .separator
        content.addSubview(separator)
        label(statusLabel, y: 534, height: 25, size: 17)
        label(distanceLabel, y: 498, height: 30, size: 22)
        label(parameterLabel, y: 473)
        label(warningLabel, y: 450, size: 11)
        warningLabel.textColor = .secondaryLabelColor
        label(detailLabel, y: 421)
        label(lastEstimateLabel, y: 397, size: 11)
        lastEstimateLabel.textColor = .secondaryLabelColor
        label(scanLabel, y: 373)
        label(logLabel, y: 351)
        label(countLabel, y: 329)
        graph.frame = NSRect(x: 14, y: 150, width: 732, height: 166)
        content.addSubview(graph)
        referenceCaption.frame = NSRect(x: 18, y: 117, width: 147, height: 20)
        exponentCaption.frame = NSRect(x: 244, y: 117, width: 105, height: 20)
        referenceField.frame = NSRect(x: 168, y: 113, width: 64, height: 25)
        exponentField.frame = NSRect(x: 350, y: 113, width: 60, height: 25)
        referenceField.setAccessibilityLabel("1 m reference RSSI / 1米参考RSSI")
        exponentField.setAccessibilityLabel("Path-loss exponent n / 路径损耗系数")
        referenceField.stringValue = String(format: "%.1f", configuration.distance.referenceRSSI)
        exponentField.stringValue = String(format: "%.1f", configuration.distance.pathLossExponent)
        for view in [referenceCaption, exponentCaption, referenceField, exponentField] { content.addSubview(view) }
        applyButton.target = self
        applyButton.action = #selector(applyParameters)
        applyButton.frame = NSRect(x: 425, y: 109, width: 126, height: 30)
        calibrateButton.target = self
        calibrateButton.action = #selector(calibrateReference)
        calibrateButton.frame = NSRect(x: 558, y: 109, width: 185, height: 30)
        content.addSubview(applyButton)
        content.addSubview(calibrateButton)
        label(calibrationLabel, y: 84, size: 11)
        label(noteLabel, y: 62, size: 11)
        label(identityLabel, y: 39, size: 11)
        calibrationLabel.textColor = .secondaryLabelColor
        noteLabel.textColor = .secondaryLabelColor
        identityLabel.textColor = .secondaryLabelColor
        rescanButton.target = self
        rescanButton.action = #selector(rescan)
        rescanButton.frame = NSRect(x: 391, y: 3, width: 118, height: 30)
        content.addSubview(rescanButton)
        chooseDeviceButton.target = self
        chooseDeviceButton.action = #selector(chooseDevice)
        chooseDeviceButton.frame = NSRect(x: 246, y: 3, width: 140, height: 30)
        content.addSubview(chooseDeviceButton)
        // Add footer breathing room without changing spacing between existing controls.
        for view in content.subviews {
            view.setFrameOrigin(NSPoint(x: view.frame.minX, y: view.frame.minY + addedBottomPadding))
        }
        // Add a header above the existing controls, preserving their spacing and footer margin.
        targetLabel.frame = NSRect(x: 16, y: content.bounds.height - 30, width: 728, height: 20)
        targetLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        targetLabel.alignment = .left
        targetLabel.lineBreakMode = .byTruncatingMiddle
        targetLabel.isSelectable = true
        content.addSubview(targetLabel)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        scanner.onObservation = { [weak self] in self?.receive($0) }
        scanner.onStatusChanged = { [weak self] in self?.render() }
        scanner.start()
        startLogStream()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.render() }
        render()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scanner.stop()
        logBackend?.stop()
        logBackend = nil
    }

    func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = t("设置未保存", "Settings not saved")
        alert.informativeText = (error as? ConfigurationError)?.message(in: configuration.language) ?? error.localizedDescription
        alert.runModal()
    }

    @objc func changeLanguage() {
        let old = configuration
        configuration.language = languagePopup.indexOfSelectedItem == 0 ? .chinese : .english
        // Never overwrite a malformed target configuration just to change UI language.
        if configurationError != nil { render(); return }
        do { try configuration.save(to: configurationURL) }
        catch { configuration = old; languagePopup.selectItem(at: old.language == .chinese ? 0 : 1); showError(error) }
        render()
    }

    @objc func applyParameters() {
        guard let reference = Double(referenceField.stringValue), let exponent = Double(exponentField.stringValue) else {
            showError(ConfigurationError.invalidDistance)
            return
        }
        var updated = configuration
        updated.distance = DistanceParameters(referenceRSSI: reference, pathLossExponent: exponent, referenceCalibrated: false)
        do {
            try updated.save(to: configurationURL)
            configuration = updated
        } catch { showError(error) }
        render()
    }

    @objc func calibrateReference() {
        let values = history.recentRSSI(at: Date())
        guard values.count >= 5 else { return }
        let alert = NSAlert()
        alert.messageText = t("确认耳机与电脑相距约 1 米？", "Is the accessory about 1 metre from this Mac?")
        alert.informativeText = t("请保持无遮挡和固定朝向。本次中位数将作为 1 米参考；n 仍是假设，不能消除墙体误差。", "Keep a clear path and fixed orientation. The median becomes the 1 m reference; n remains assumed and walls can still distort estimates.")
        alert.addButton(withTitle: t("确认校准", "Calibrate"))
        alert.addButton(withTitle: t("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Modal dialogs may remain open for a long time: re-check freshness.
        let freshValues = history.recentRSSI(at: Date())
        guard freshValues.count >= 5, let freshValue = median(freshValues) else { return }
        var updated = configuration
        updated.distance.referenceRSSI = freshValue
        updated.distance.referenceCalibrated = true
        do {
            try updated.save(to: configurationURL)
            configuration = updated
            referenceField.stringValue = String(format: "%.1f", freshValue)
        } catch { showError(error) }
        render()
    }

    @objc func chooseDevice() {
        devicePicker = DevicePicker(parent: window, language: configuration.language,
            showDistances: configuration.showDiscoveryDistances,
            provider: { [weak self] in self.map { Array($0.scanner.nearby.values) } ?? [] },
            onDistanceOptionChanged: { [weak self] enabled in self?.setDiscoveryDistances(enabled) ?? false },
            onChoose: { [weak self] identifier in self?.setTarget(identifier) })
    }

    func setDiscoveryDistances(_ enabled: Bool) -> Bool {
        var updated = configuration
        updated.showDiscoveryDistances = enabled
        do {
            try updated.save(to: configurationURL)
            configuration = updated
            return true
        } catch {
            showError(error)
            return false
        }
    }

    func setTarget(_ identifier: UUID?) {
        guard configurationError == nil else { return }
        var updated = configuration
        updated.peripheralIdentifier = identifier?.uuidString
        // A different device must never inherit the previous device's 1 m calibration.
        updated.distance = DistanceParameters()
        do {
            try updated.save(to: configurationURL)
            configuration = updated
            history = SignalHistory()
            coreMatches = 0
            systemMatches = 0
            referenceField.stringValue = "-59.0"
            exponentField.stringValue = "2.5"
            logBackend?.stop()
            logBackend = nil
            if identifier == nil { startLogStream() }
        } catch { showError(error) }
        render()
    }

    @objc func rescan() {
        scanner.rescan()
        if logBackend?.isRunning != true { startLogStream() }
        render()
    }

    private func receive(_ observation: Observation<BLEAdvertisement>) {
        let advertisement = observation.payload
        let source: SignalSource
        if let id = configuration.peripheralIdentifier {
            guard advertisement.identifier.uuidString == id.uppercased() else { return }
            source = .selectedPeripheral
        } else {
            guard let data = advertisement.manufacturerData,
                  matchesHistoricalPayload(data, prefix: configuration.payloadBytes) else { return }
            source = .historicalPayload
        }
        coreMatches += 1
        history.append(SignalSample(date: observation.context.observedAt,
                                    rssi: advertisement.rssi, source: source))
    }

    private func startLogStream() {
        guard configuration.peripheralIdentifier == nil, let identifier = configuration.caseIdentifier else { return }
        if let backend = logBackend { backend.start(); return }
        let backend = AirPodsLogBackend(identifier: identifier, sessionID: sessionID,
                                       startedAt: history.startedAt)
        backend.onObservation = { [weak self] observation in
            guard let self else { return }
            self.history.append(SignalSample(date: observation.context.observedAt,
                rssi: observation.payload.rssi, source: .systemIdentifier))
            self.systemMatches += 1
        }
        backend.onStatusChanged = { [weak self] in self?.render() }
        logBackend = backend
        backend.start()
    }

    private func bluetoothStatus() -> String {
        switch scanner.state {
        case .poweredOn: return t("正在扫描", "Scanning")
        case .poweredOff: return t("已关闭，请打开蓝牙", "Off; turn Bluetooth on")
        case .unauthorized: return t("无权限，请到隐私设置允许蓝牙", "Not authorised; allow Bluetooth in Privacy settings")
        case .unsupported: return t("本机不支持", "Unsupported")
        case .resetting: return t("正在重置", "Resetting")
        default: return t("等待初始化", "Initialising")
        }
    }

    func render() {
        let now = Date(), values = history.recentRSSI(at: Date())
        let parameters = configuration.distance
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let targetText = trackingTargetText(configuration: configuration, nearby: scanner.nearby)
        if targetLabel.stringValue != targetText { targetLabel.stringValue = targetText }
        targetLabel.setAccessibilityLabel(t("当前选择的追踪目标", "Selected tracking target"))
        targetLabel.toolTip = targetText + t("\n名称来自发现记录；选择标识不代表当前在场或身份认证。", "\nName comes from discovery records; selection is not proof of current presence or ownership.")
        window?.title = t("BLE 信号雷达 v\(version) · 0.5 秒刷新", "BLE Signal Radar v\(version) · 0.5 s UI refresh")
        if let item = NSApp.mainMenu?.items.first?.submenu?.items.first { item.title = t("退出信号雷达", "Quit Signal Radar") }
        if let sample = history.latest {
            let age = max(0, now.timeIntervalSince(sample.date)), fresh = history.isFresh(at: now)
            bigLabel.stringValue = fresh ? "\(sample.rssi) dBm" : "--"
            bigLabel.textColor = fresh ? signalColor(sample.rssi) : .secondaryLabelColor
            statusLabel.stringValue = fresh ? t("刚收到更新 · \(String(format: "%.1f", age)) 秒前", "New update · \(String(format: "%.1f", age)) s ago") : t("暂无新样本 · 上次更新 \(Int(age)) 秒前", "No fresh sample · last update \(Int(age)) s ago")
            let source: String
            switch sample.source {
            case .systemIdentifier: source = t("系统目标 ID", "System target ID")
            case .historicalPayload: source = t("历史指纹候选，身份未验证", "Historical payload candidate; identity unverified")
            case .selectedPeripheral: source = t("所选 BLE 标识，请核实设备身份", "Selected BLE identifier; verify device identity")
            }
            detailLabel.stringValue = "\(clock.string(from: sample.date)) / \(sample.rssi) dBm / \(source)"
            if let number = parameters.estimateText(rssi: Double(sample.rssi)) {
                let state = fresh ? t("单次样本", "single sample") : t("历史，非当前", "HISTORICAL, not current")
                let calibration = parameters.referenceCalibrated ? t("1米参考已设，n仍为假设", "1 m ref set; n assumed") : t("未校准", "uncalibrated")
                lastEstimateLabel.stringValue = t("上次单样本模型参考：≈ \(number) 米 · \(Int(age)) 秒前 · \(state) · \(calibration)", "Last-sample model ref: ≈ \(number) m · \(Int(age)) s ago · \(state) · \(calibration)")
            } else { lastEstimateLabel.stringValue = t("上次单样本模型参考：--", "Last-sample model ref: --") }
        } else {
            bigLabel.stringValue = "--"
            statusLabel.stringValue = t("暂无目标数据 · 已等待 \(Int(now.timeIntervalSince(history.startedAt))) 秒", "No target data · waiting \(Int(now.timeIntervalSince(history.startedAt))) s")
            detailLabel.stringValue = t("没有新样本，不能判断位置", "No fresh sample; location cannot be inferred")
            lastEstimateLabel.stringValue = t("上次单样本模型参考：-- · 本次尚无目标样本", "Last-sample model ref: -- · no target sample this session")
        }
        lastEstimateLabel.toolTip = t("按上次原始RSSI和当前模型参数计算；不是当前距离，也不是近期样本中位数。", "Computed from the last raw RSSI and current parameters, not a current distance or recent-sample median.")
        rssiHeading.stringValue = t("接收信号强度（dBm）", "Signal strength (dBm)")
        distanceHeading.stringValue = t("估算距离（米）", "Estimated distance (m)")
        bigLabel.setAccessibilityLabel(t("最新信号强度，单位dBm", "Latest signal strength in dBm"))
        bigDistanceLabel.setAccessibilityLabel(t("模型估算距离，单位米", "Model-estimated distance in metres"))
        bigDistanceLabel.toolTip = t("近期同源RSSI中位数计算的模型参考，不是实测距离。超过5秒无新样本时显示--。", "Model reference from the recent same-source median RSSI, not measured distance. Shows -- after 5 seconds without a fresh sample.")
        if let value = median(values), let number = parameters.estimateText(rssi: value) {
            bigDistanceLabel.stringValue = "≈ \(number) m"
            bigDistanceLabel.textColor = .labelColor
            let reference = parameters.referenceCalibrated ? t("1米参考已校准，n仍为假设", "1 m reference set; n assumed") : t("未校准，仅模型参考", "Uncalibrated model only")
            distanceLabel.stringValue = t("距离模型 · \(reference)", "Distance model · \(reference)")
        } else {
            bigDistanceLabel.stringValue = "--"
            bigDistanceLabel.textColor = .secondaryLabelColor
            distanceLabel.stringValue = t("距离暂不可用 · 等待新的目标样本", "Distance unavailable · awaiting fresh target samples")
        }
        parameterLabel.stringValue = t("参考：1米 \(String(format: "%.1f", parameters.referenceRSSI)) dBm，n=\(parameters.pathLossExponent)；近期 \(values.count) 条同源样本取中位数", "Reference: \(String(format: "%.1f", parameters.referenceRSSI)) dBm at 1 m, n=\(parameters.pathLossExponent); median of \(values.count) recent same-source samples")
        warningLabel.stringValue = t("墙、柜子、人体和朝向都可能使估算严重失真；这不是实际测距或精确定位。", "Walls, cabinets, bodies and orientation can cause large errors. This is NOT measured distance or precision finding.")
        scanLabel.stringValue = t("蓝牙：\(bluetoothStatus()) ｜ 回调 \(scanner.callbacks) 次 / 累计 \(scanner.identifierCount) 个 BLE 标识", "Bluetooth: \(bluetoothStatus()) | \(scanner.callbacks) callbacks / \(scanner.identifierCount) cumulative BLE identifiers")
        if let error = configurationError { logLabel.stringValue = t("配置读取失败：", "Configuration error: ") + ((error as? ConfigurationError)?.message(in: configuration.language) ?? error.localizedDescription) }
        else if let error = logFailure { logLabel.stringValue = t("系统事件异常：", "System event error: ") + error }
        else if configuration.peripheralIdentifier != nil { logLabel.stringValue = t("系统事件：通用 BLE 模式下不使用 AirPods 日志", "System events: AirPods log channel is off in generic BLE mode") }
        else if configuration.caseIdentifier == nil { logLabel.stringValue = t("系统事件：未配置目标 ID", "System events: no target ID configured") }
        else { logLabel.stringValue = t("系统事件：监听启动后的目标更新", "System events: listening for new target updates") }
        countLabel.stringValue = t("本次目标更新：系统 ID \(systemMatches) 条 / BLE 匹配 \(coreMatches) 条", "Target updates this session: system ID \(systemMatches) / BLE matches \(coreMatches)")
        referenceCaption.stringValue = t("1米参考 RSSI (dBm)", "1 m reference (dBm)")
        exponentCaption.stringValue = t("损耗系数 n", "Path-loss n")
        applyButton.title = t("应用参数", "Apply parameters")
        calibrateButton.title = t("已放在1米：校准", "At 1 metre: calibrate")
        calibrateButton.isEnabled = values.count >= 5 && configurationError == nil
        applyButton.isEnabled = configurationError == nil
        chooseDeviceButton.isEnabled = configurationError == nil
        calibrationLabel.stringValue = t("校准要求：目标距电脑约1米，固定朝向、无遮挡，最近10秒至少5条同源样本。", "Calibration: accessory at 1 m, fixed orientation, clear path, at least 5 same-source samples in 10 s.")
        noteLabel.stringValue = t("0.5秒刷新界面，不保证收包频率；无样本不补点，5秒后清空当前估算。", "0.5 s UI refresh, not a guaranteed packet rate. No invented samples; estimates expire after 5 s.")
        if configuration.peripheralIdentifier != nil {
            identityLabel.stringValue = t("追踪手动选择的 BLE 目标；更换目标会重置距离校准", "Tracking your selected BLE target; changing targets resets distance calibration")
        } else {
            identityLabel.stringValue = configuration.payloadBytes.isEmpty && configuration.caseIdentifier == nil ? t("点击“选择设备”开始；显示旧电量不代表设备就在附近", "Choose a device to begin; an old battery reading does not prove proximity") : t("使用本地配件配置；候选匹配不是身份认证", "Using local accessory configuration; candidate matching is not authentication")
        }
        chooseDeviceButton.title = t("选择设备", "Choose device")
        rescanButton.title = t("重新扫描", "Rescan")
        graph.language = configuration.language
        graph.setAccessibilityLabel(t("过去60秒实际样本；空白表示没有样本", "Actual samples over 60 seconds; gaps mean no samples"))
        graph.samples = history.samples
        graph.needsDisplay = true
        if devicePicker?.panel.isVisible == true { devicePicker?.refresh() }
    }
}

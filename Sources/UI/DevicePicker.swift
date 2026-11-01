import Cocoa

final class DevicePicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 860, height: 450),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let table = NSTableView()
    var rows: [NearbyPeripheral] = []
    let provider: () -> [NearbyPeripheral]
    let onChoose: (UUID?) -> Void
    let onDistanceOptionChanged: (Bool) -> Bool
    let language: AppLanguage
    let chooseButton = NSButton()
    let distanceToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    weak var parent: NSWindow?

    func t(_ chinese: String, _ english: String) -> String { language == .chinese ? chinese : english }

    init(parent: NSWindow, language: AppLanguage, showDistances: Bool,
         provider: @escaping () -> [NearbyPeripheral],
         onDistanceOptionChanged: @escaping (Bool) -> Bool,
         onChoose: @escaping (UUID?) -> Void) {
        self.parent = parent
        self.language = language
        self.provider = provider
        self.onChoose = onChoose
        self.onDistanceOptionChanged = onDistanceOptionChanged
        super.init()
        panel.title = t("选择正在广播的 BLE 目标", "Choose an advertising BLE target")
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let note = NSTextField(wrappingLabelWithString: t(
            "只列最近60秒收到的广播；名字和厂商不能验证身份。请用你已知的设备做移动/远近对照，再选目标。标识可能轮换。",
            "Advertisements seen within 60 s only. Names and manufacturers do not prove ownership. Verify by moving a known device before choosing. Identifiers may rotate."))
        note.frame = NSRect(x: 16, y: 394, width: 828, height: 44)
        panel.contentView!.addSubview(note)
        distanceToggle.title = t("显示已扫描BLE设备的估算距离（统一默认参数，未校准）", "Show model distances for scanned BLE devices (default assumptions; uncalibrated)")
        distanceToggle.frame = NSRect(x: 16, y: 359, width: 828, height: 26)
        distanceToggle.state = showDistances ? .on : .off
        distanceToggle.target = self
        distanceToggle.action = #selector(toggleDistances)
        distanceToggle.toolTip = t("统一使用1米 -59 dBm、n=2.5；不是实测距离，不使用其他目标的校准。超过5秒无更新则显示--。", "Uses -59 dBm at 1 m and n=2.5 for each row, not measured distance or another target's calibration. No update for 5 s means --.")
        panel.contentView!.addSubview(distanceToggle)
        let columns: [(String, String, CGFloat)] = [
            ("name", t("广播名称", "Advertised name"), 246),
            ("id", t("扫描标识", "Scan ID"), 96),
            ("rssi", "dBm", 64),
            ("distance", t("估算米数（未校准）", "Model m (uncal.)"), 144),
            ("age", t("多久前", "Age"), 80),
            ("vendor", t("厂商代码", "Company ID"), 136)
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.isHidden = id == "distance" && !showDistances
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 26
        table.allowsEmptySelection = true
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 67, width: 828, height: 276))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = table
        panel.contentView!.addSubview(scroll)
        let accessory = NSButton(title: t("使用本地配件配置", "Use accessory configuration"), target: self, action: #selector(useConfiguration))
        accessory.frame = NSRect(x: 16, y: 16, width: 240, height: 32)
        panel.contentView!.addSubview(accessory)
        let cancel = NSButton(title: t("取消", "Cancel"), target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 597, y: 16, width: 100, height: 32)
        panel.contentView!.addSubview(cancel)
        chooseButton.title = t("追踪所选目标", "Track selection")
        chooseButton.target = self
        chooseButton.action = #selector(choose)
        chooseButton.frame = NSRect(x: 697, y: 16, width: 147, height: 32)
        panel.contentView!.addSubview(chooseButton)
        refresh()
        parent.beginSheet(panel)
    }

    func refresh() {
        let selected = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].identifier : nil
        let candidates = provider().filter { Date().timeIntervalSince($0.lastSeen) < 60 }
        let lookup = Dictionary(uniqueKeysWithValues: candidates.map { ($0.identifier, $0) })
        // Preserve row order while the user chooses; append new rows instead of moving targets.
        rows = rows.compactMap { lookup[$0.identifier] }
        let existing = Set(rows.map(\.identifier))
        rows.append(contentsOf: candidates.filter { !existing.contains($0.identifier) }.sorted { $0.rssi > $1.rssi })
        table.reloadData()
        if let selected, let index = rows.firstIndex(where: { $0.identifier == selected }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else { table.deselectAll(nil) }
        updateChooseButton()
    }

    @objc func toggleDistances() {
        let requested = distanceToggle.state == .on
        if !onDistanceOptionChanged(requested) { distanceToggle.state = requested ? .off : .on }
        table.tableColumns.first(where: { $0.identifier.rawValue == "distance" })?.isHidden = distanceToggle.state != .on
        table.reloadData()
        updateChooseButton()
    }

    func updateChooseButton() {
        chooseButton.isEnabled = rows.indices.contains(table.selectedRow) && rows[table.selectedRow].isFresh(at: Date())
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateChooseButton() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let item = rows[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "name": text = item.name ?? t("未命名 BLE 设备", "Unnamed BLE device")
        case "id": text = String(item.identifier.uuidString.prefix(8))
        case "rssi": text = "\(item.rssi)"
        case "distance":
            text = distanceToggle.state == .on ? item.uncalibratedDistanceText(at: Date()).map { "≈ \($0)" } ?? "--" : "--"
        case "age": text = "\(max(0, Int(Date().timeIntervalSince(item.lastSeen)))) " + t("秒", "s")
        default: text = item.manufacturer ?? "--"
        }
        let cell = NSTextField(labelWithString: text)
        cell.lineBreakMode = .byTruncatingTail
        if !item.isFresh(at: Date()) { cell.textColor = .secondaryLabelColor }
        if tableColumn?.identifier.rawValue == "distance" {
            cell.toolTip = distanceToggle.toolTip
        }
        return cell
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finish(); return false }
    func finish() { parent?.endSheet(panel); panel.orderOut(nil) }
    @objc func cancel() { finish() }
    @objc func useConfiguration() { finish(); onChoose(nil) }
    @objc func choose() {
        guard rows.indices.contains(table.selectedRow) else { return }
        let item = rows[table.selectedRow]
        guard item.isFresh(at: Date()) else {
            let alert = NSAlert()
            alert.messageText = t("所选设备暂无新广播", "The selected device has no fresh advertisement")
            alert.informativeText = t("等待新样本后再选择，避免追踪旧记录。", "Wait for a new sample before choosing, to avoid tracking an old record.")
            alert.runModal()
            return
        }
        finish()
        onChoose(item.identifier)
    }
}

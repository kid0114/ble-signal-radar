import Cocoa

func signalColor(_ rssi: Int) -> NSColor {
    if rssi < -85 { return .systemRed }
    if rssi < -70 { return .systemOrange }
    if rssi < -55 { return .systemYellow }
    return .systemGreen
}

final class GraphView: NSView {
    var samples: [SignalSample] = []
    var language = AppLanguage.chinese
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
        bounds.fill()
        let plot = bounds.insetBy(dx: 38, dy: 20)
        let now = Date(), start = now.addingTimeInterval(-60)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.lightGray
        ]
        for value in [-100, -70, -40] {
            let y = plot.minY + CGFloat(value + 105) / 70 * plot.height
            NSColor.darkGray.setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            line.stroke()
            ("\(value)" as NSString).draw(at: NSPoint(x: 5, y: y - 6), withAttributes: attributes)
        }
        let left = language == .chinese ? "60 秒前" : "60 s ago"
        let right = language == .chinese ? "现在" : "Now"
        (left as NSString).draw(at: NSPoint(x: plot.minX, y: 2), withAttributes: attributes)
        (right as NSString).draw(at: NSPoint(x: plot.maxX - 25, y: 2), withAttributes: attributes)
        var previous: (Date, NSPoint)?
        for sample in samples where sample.date >= start && sample.date <= now {
            let x = plot.minX + CGFloat(sample.date.timeIntervalSince(start) / 60) * plot.width
            let y = plot.minY + CGFloat(max(-105, min(-35, sample.rssi)) + 105) / 70 * plot.height
            let point = NSPoint(x: x, y: y)
            signalColor(sample.rssi).setStroke()
            signalColor(sample.rssi).setFill()
            if let (date, oldPoint) = previous, sample.date.timeIntervalSince(date) <= 3 {
                let line = NSBezierPath()
                line.lineWidth = 2
                line.move(to: oldPoint)
                line.line(to: point)
                line.stroke()
            }
            NSBezierPath(ovalIn: NSRect(x: x - 3, y: y - 3, width: 6, height: 6)).fill()
            previous = (sample.date, point)
        }
    }
}

import AppKit
let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let outer = NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 968, height: 968), xRadius: 220, yRadius: 220)
NSGradient(starting: NSColor(calibratedRed: 0.17, green: 0.19, blue: 0.25, alpha: 1), ending: NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.08, alpha: 1))!.draw(in: outer, angle: -90)
let frame = NSRect(x: 170, y: 275, width: 684, height: 474)
let monitor = NSBezierPath(roundedRect: frame, xRadius: 55, yRadius: 55)
NSColor(calibratedRed: 1, green: 0.64, blue: 0.27, alpha: 1).setStroke(); monitor.lineWidth = 26; monitor.stroke()
let inner = NSBezierPath(roundedRect: frame.insetBy(dx: 40, dy: 40), xRadius: 24, yRadius: 24)
NSGradient(starting: NSColor(calibratedRed: 0.5, green: 0.25, blue: 0.15, alpha: 1), ending: NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.22, alpha: 1))!.draw(in: inner, angle: -70)
let stand = NSBezierPath(); stand.move(to: NSPoint(x: 512, y: 255)); stand.line(to: NSPoint(x: 512, y: 190)); stand.move(to: NSPoint(x: 414, y: 186)); stand.line(to: NSPoint(x: 610, y: 186)); stand.lineWidth = 24; stand.lineCapStyle = .round; NSColor(calibratedWhite: 0.65, alpha: 1).setStroke(); stand.stroke()
for x in stride(from: 235, through: 790, by: 70) { NSColor(calibratedRed: 1, green: 0.72, blue: 0.38, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: 795, width: 35, height: 12), xRadius: 6, yRadius: 6).fill() }
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

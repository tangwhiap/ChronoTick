import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output-directory>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let fileManager = FileManager.default
try? fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let iconDefinitions: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconDefinitions {
    let image = makeIcon(size: CGFloat(size))
    let destination = outputDirectory.appendingPathComponent(name)
    try savePNG(image: image, to: destination)
}

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let backgroundPath = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: size * 0.23, yRadius: size * 0.23)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.98, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.74, blue: 0.79, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.34, blue: 0.77, alpha: 1)
    ])!
    gradient.draw(in: backgroundPath, angle: -35)

    let glowRect = NSRect(x: size * 0.18, y: size * 0.60, width: size * 0.64, height: size * 0.26)
    let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: size * 0.13, yRadius: size * 0.13)
    NSColor.white.withAlphaComponent(0.16).setFill()
    glowPath.fill()

    drawGrid(size: size)
    drawClock(size: size)
    drawTick(size: size)

    image.unlockFocus()
    return image
}

func drawGrid(size: CGFloat) {
    let gridRect = NSRect(x: size * 0.18, y: size * 0.18, width: size * 0.64, height: size * 0.64)
    let gridPath = NSBezierPath(roundedRect: gridRect, xRadius: size * 0.17, yRadius: size * 0.17)
    NSColor.white.withAlphaComponent(0.10).setStroke()
    gridPath.lineWidth = max(1.0, size * 0.012)
    gridPath.stroke()

    let step = size * 0.12
    for index in 1...4 {
        let offset = CGFloat(index) * step
        let vertical = NSBezierPath()
        vertical.move(to: CGPoint(x: gridRect.minX + offset, y: gridRect.minY + size * 0.04))
        vertical.line(to: CGPoint(x: gridRect.minX + offset, y: gridRect.maxY - size * 0.04))
        NSColor.white.withAlphaComponent(0.08).setStroke()
        vertical.lineWidth = max(0.8, size * 0.006)
        vertical.stroke()

        let horizontal = NSBezierPath()
        horizontal.move(to: CGPoint(x: gridRect.minX + size * 0.04, y: gridRect.minY + offset))
        horizontal.line(to: CGPoint(x: gridRect.maxX - size * 0.04, y: gridRect.minY + offset))
        horizontal.lineWidth = max(0.8, size * 0.006)
        horizontal.stroke()
    }
}

func drawClock(size: CGFloat) {
    let circleRect = NSRect(x: size * 0.24, y: size * 0.24, width: size * 0.52, height: size * 0.52)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    NSColor.white.withAlphaComponent(0.92).setStroke()
    circlePath.lineWidth = size * 0.055
    circlePath.stroke()

    let center = CGPoint(x: circleRect.midX, y: circleRect.midY)

    let hourHand = NSBezierPath()
    hourHand.move(to: center)
    hourHand.line(to: CGPoint(x: center.x, y: center.y + size * 0.11))
    hourHand.lineWidth = size * 0.05
    hourHand.lineCapStyle = .round
    NSColor.white.setStroke()
    hourHand.stroke()

    let minuteHand = NSBezierPath()
    minuteHand.move(to: center)
    minuteHand.line(to: CGPoint(x: center.x + size * 0.10, y: center.y - size * 0.07))
    minuteHand.lineWidth = size * 0.04
    minuteHand.lineCapStyle = .round
    minuteHand.stroke()

    let centerDot = NSBezierPath(ovalIn: NSRect(x: center.x - size * 0.026, y: center.y - size * 0.026, width: size * 0.052, height: size * 0.052))
    NSColor.white.setFill()
    centerDot.fill()
}

func drawTick(size: CGFloat) {
    let tick = NSBezierPath()
    tick.move(to: CGPoint(x: size * 0.39, y: size * 0.31))
    tick.line(to: CGPoint(x: size * 0.49, y: size * 0.22))
    tick.line(to: CGPoint(x: size * 0.68, y: size * 0.47))
    tick.lineCapStyle = .round
    tick.lineJoinStyle = .round
    tick.lineWidth = size * 0.075
    NSColor(calibratedRed: 1.0, green: 0.73, blue: 0.20, alpha: 1.0).setStroke()
    tick.stroke()

    let accentDot = NSBezierPath(ovalIn: NSRect(x: size * 0.63, y: size * 0.60, width: size * 0.11, height: size * 0.11))
    NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.33, alpha: 0.95).setFill()
    accentDot.fill()
}

func savePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ChronoTickIcon", code: 1)
    }
    try png.write(to: url)
}

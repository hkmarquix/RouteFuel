import AppKit

let size = CGSize(width: 1024, height: 1024)

func color(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawBackground() {
    let rect = CGRect(origin: .zero, size: size)
    let gradient = NSGradient(colors: [
        color(0x103B66),
        color(0x0F6C7A),
        color(0x34B3A0)
    ])!
    gradient.draw(in: rect, angle: -35)

    color(0xA6F0E3, alpha: 0.10).setFill()
    NSBezierPath(ovalIn: CGRect(x: 104, y: 710, width: 252, height: 252)).fill()

    color(0x0A1F3D, alpha: 0.14).setFill()
    NSBezierPath(ovalIn: CGRect(x: 694, y: 86, width: 250, height: 250)).fill()
}

func drawSymbol() {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x062247, alpha: 0.22)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = CGSize(width: 0, height: -10)
    shadow.set()

    let pumpGradient = NSGradient(colors: [color(0xFFF8EE), color(0xECF5F1)])!
    let pumpPath = roundedRectPath(CGRect(x: 250, y: 202, width: 470, height: 620), radius: 132)
    pumpGradient.draw(in: pumpPath, angle: -90)

    NSGraphicsContext.restoreGraphicsState()

    color(0x0D5468, alpha: 0.10).setStroke()
    pumpPath.lineWidth = 4
    pumpPath.stroke()

    let nozzleTop = NSBezierPath()
    nozzleTop.lineWidth = 26
    nozzleTop.lineCapStyle = .round
    nozzleTop.move(to: CGPoint(x: 600, y: 692))
    nozzleTop.line(to: CGPoint(x: 676, y: 692))
    color(0xFFBE67).setStroke()
    nozzleTop.stroke()

    let hose = NSBezierPath()
    hose.lineWidth = 34
    hose.lineCapStyle = .round
    hose.lineJoinStyle = .round
    hose.move(to: CGPoint(x: 720, y: 644))
    hose.curve(to: CGPoint(x: 796, y: 554),
               controlPoint1: CGPoint(x: 764, y: 640),
               controlPoint2: CGPoint(x: 796, y: 612))
    hose.curve(to: CGPoint(x: 748, y: 392),
               controlPoint1: CGPoint(x: 796, y: 488),
               controlPoint2: CGPoint(x: 782, y: 430))
    hose.line(to: CGPoint(x: 704, y: 330))
    color(0x163F69, alpha: 0.92).setStroke()
    hose.stroke()

    let nozzle = NSBezierPath()
    nozzle.lineWidth = 24
    nozzle.lineCapStyle = .round
    nozzle.move(to: CGPoint(x: 694, y: 320))
    nozzle.line(to: CGPoint(x: 734, y: 290))
    color(0xFFBE67).setStroke()
    nozzle.stroke()

    let routeLine = NSBezierPath()
    routeLine.lineWidth = 62
    routeLine.lineCapStyle = .round
    routeLine.lineJoinStyle = .round
    routeLine.move(to: CGPoint(x: 378, y: 640))
    routeLine.curve(to: CGPoint(x: 426, y: 558),
                    controlPoint1: CGPoint(x: 378, y: 606),
                    controlPoint2: CGPoint(x: 394, y: 576))
    routeLine.curve(to: CGPoint(x: 570, y: 530),
                    controlPoint1: CGPoint(x: 454, y: 524),
                    controlPoint2: CGPoint(x: 516, y: 514))
    routeLine.curve(to: CGPoint(x: 530, y: 414),
                    controlPoint1: CGPoint(x: 608, y: 542),
                    controlPoint2: CGPoint(x: 594, y: 450))
    routeLine.curve(to: CGPoint(x: 430, y: 334),
                    controlPoint1: CGPoint(x: 500, y: 374),
                    controlPoint2: CGPoint(x: 468, y: 346))
    color(0x1F8AA2).setStroke()
    routeLine.stroke()

    let roadStripe = NSBezierPath()
    roadStripe.lineWidth = 18
    roadStripe.lineCapStyle = .round
    roadStripe.move(to: CGPoint(x: 380, y: 626))
    roadStripe.curve(to: CGPoint(x: 418, y: 560),
                     controlPoint1: CGPoint(x: 380, y: 600),
                     controlPoint2: CGPoint(x: 392, y: 576))
    roadStripe.curve(to: CGPoint(x: 560, y: 532),
                     controlPoint1: CGPoint(x: 446, y: 530),
                     controlPoint2: CGPoint(x: 506, y: 522))
    roadStripe.curve(to: CGPoint(x: 520, y: 422),
                     controlPoint1: CGPoint(x: 596, y: 540),
                     controlPoint2: CGPoint(x: 582, y: 452))
    roadStripe.curve(to: CGPoint(x: 436, y: 358),
                     controlPoint1: CGPoint(x: 494, y: 392),
                     controlPoint2: CGPoint(x: 468, y: 372))
    color(0xFFFFFF, alpha: 0.92).setStroke()
    roadStripe.stroke()

    color(0xFF7F32).setFill()
    NSBezierPath(ovalIn: CGRect(x: 330, y: 610, width: 94, height: 94)).fill()

    let centerDot = NSBezierPath(ovalIn: CGRect(x: 359, y: 639, width: 36, height: 36))
    color(0xFFF8EF).setFill()
    centerDot.fill()
}

let image = NSImage(size: size)
image.lockFocus()
drawBackground()
drawSymbol()
image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    fatalError("Failed to render icon")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let files = [
    "routefuel-app-icon.png",
    "routefuel-app-icon-dark.png",
    "routefuel-app-icon-tinted.png"
]

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for file in files {
    try png.write(to: outputDirectory.appendingPathComponent(file))
}

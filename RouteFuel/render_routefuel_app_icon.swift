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
    color(0xFFFFFF).setFill()
    NSBezierPath(rect: rect).fill()
}

func drawSymbol() {
    let pinOutline = NSBezierPath()
    pinOutline.lineWidth = 42
    pinOutline.lineCapStyle = .round
    pinOutline.lineJoinStyle = .round
    pinOutline.move(to: CGPoint(x: 282, y: 258))
    pinOutline.curve(to: CGPoint(x: 742, y: 258),
                     controlPoint1: CGPoint(x: 360, y: 142),
                     controlPoint2: CGPoint(x: 664, y: 142))
    pinOutline.curve(to: CGPoint(x: 650, y: 568),
                     controlPoint1: CGPoint(x: 742, y: 386),
                     controlPoint2: CGPoint(x: 724, y: 482))
    pinOutline.curve(to: CGPoint(x: 512, y: 836),
                     controlPoint1: CGPoint(x: 612, y: 664),
                     controlPoint2: CGPoint(x: 560, y: 756))
    pinOutline.curve(to: CGPoint(x: 374, y: 568),
                     controlPoint1: CGPoint(x: 464, y: 756),
                     controlPoint2: CGPoint(x: 412, y: 664))
    pinOutline.curve(to: CGPoint(x: 282, y: 258),
                     controlPoint1: CGPoint(x: 300, y: 482),
                     controlPoint2: CGPoint(x: 282, y: 386))
    color(0x2F6EAE).setStroke()
    pinOutline.stroke()

    let road = NSBezierPath()
    road.move(to: CGPoint(x: 512, y: 836))
    road.curve(to: CGPoint(x: 402, y: 612),
               controlPoint1: CGPoint(x: 468, y: 770),
               controlPoint2: CGPoint(x: 426, y: 688))
    road.curve(to: CGPoint(x: 362, y: 486),
               controlPoint1: CGPoint(x: 384, y: 574),
               controlPoint2: CGPoint(x: 374, y: 524))
    road.line(to: CGPoint(x: 418, y: 486))
    road.curve(to: CGPoint(x: 452, y: 598),
               controlPoint1: CGPoint(x: 424, y: 526),
               controlPoint2: CGPoint(x: 434, y: 568))
    road.curve(to: CGPoint(x: 534, y: 780),
               controlPoint1: CGPoint(x: 470, y: 658),
               controlPoint2: CGPoint(x: 506, y: 730))
    road.line(to: CGPoint(x: 512, y: 836))
    road.close()

    let roadMirror = NSBezierPath()
    roadMirror.move(to: CGPoint(x: 512, y: 836))
    roadMirror.curve(to: CGPoint(x: 622, y: 612),
                     controlPoint1: CGPoint(x: 556, y: 770),
                     controlPoint2: CGPoint(x: 598, y: 688))
    roadMirror.curve(to: CGPoint(x: 662, y: 486),
                     controlPoint1: CGPoint(x: 640, y: 574),
                     controlPoint2: CGPoint(x: 650, y: 524))
    roadMirror.line(to: CGPoint(x: 606, y: 486))
    roadMirror.curve(to: CGPoint(x: 572, y: 598),
                     controlPoint1: CGPoint(x: 600, y: 526),
                     controlPoint2: CGPoint(x: 590, y: 568))
    roadMirror.curve(to: CGPoint(x: 490, y: 780),
                     controlPoint1: CGPoint(x: 554, y: 658),
                     controlPoint2: CGPoint(x: 518, y: 730))
    roadMirror.line(to: CGPoint(x: 512, y: 836))
    roadMirror.close()

    color(0x24314B).setFill()
    road.fill()
    roadMirror.fill()

    let centerLine = NSBezierPath()
    centerLine.lineWidth = 14
    centerLine.lineCapStyle = .round
    centerLine.move(to: CGPoint(x: 512, y: 764))
    centerLine.curve(to: CGPoint(x: 512, y: 692),
                     controlPoint1: CGPoint(x: 512, y: 744),
                     controlPoint2: CGPoint(x: 512, y: 716))
    centerLine.move(to: CGPoint(x: 512, y: 652))
    centerLine.curve(to: CGPoint(x: 520, y: 604),
                     controlPoint1: CGPoint(x: 514, y: 638),
                     controlPoint2: CGPoint(x: 518, y: 620))
    color(0xFFFFFF).setStroke()
    centerLine.stroke()

    let pump = roundedRectPath(CGRect(x: 416, y: 310, width: 132, height: 178), radius: 18)
    color(0x17C493).setFill()
    pump.fill()

    color(0xFFFFFF).setFill()
    roundedRectPath(CGRect(x: 440, y: 432, width: 84, height: 40), radius: 8).fill()

    let pumpBase = NSBezierPath()
    pumpBase.lineWidth = 14
    pumpBase.lineCapStyle = .round
    pumpBase.move(to: CGPoint(x: 402, y: 296))
    pumpBase.line(to: CGPoint(x: 558, y: 296))
    color(0x17C493).setStroke()
    pumpBase.stroke()

    let hose = NSBezierPath()
    hose.lineWidth = 14
    hose.lineCapStyle = .round
    hose.lineJoinStyle = .round
    hose.move(to: CGPoint(x: 548, y: 438))
    hose.curve(to: CGPoint(x: 602, y: 374),
               controlPoint1: CGPoint(x: 580, y: 432),
               controlPoint2: CGPoint(x: 602, y: 412))
    hose.line(to: CGPoint(x: 594, y: 346))
    color(0x17C493).setStroke()
    hose.stroke()

    let nozzle = NSBezierPath()
    nozzle.lineWidth = 12
    nozzle.lineCapStyle = .round
    nozzle.move(to: CGPoint(x: 590, y: 342))
    nozzle.line(to: CGPoint(x: 574, y: 326))
    nozzle.stroke()
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

import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let terracotta = CGColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
let terracottaDark = CGColor(srgbRed: 0xC4 / 255, green: 0x62 / 255, blue: 0x3F / 255, alpha: 1)
let cream = CGColor(srgbRed: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEE / 255, alpha: 1)
let ink = CGColor(srgbRed: 0x2C / 255, green: 0x2B / 255, blue: 0x28 / 255, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)
let black = CGColor(gray: 0, alpha: 1)

func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0
    for step in 0...720 {
        let t = Double(step) / 720 * 2 * .pi
        let x = pow(abs(cos(t)), 2 / n) * (cos(t) < 0 ? -1 : 1)
        let y = pow(abs(sin(t)), 2 / n) * (sin(t) < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func crab(_ context: CGContext, in rect: CGRect, template: Bool) {
    let unit = rect.width / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit) }
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect { CGRect(x: rect.minX + (x - r) * unit, y: rect.minY + (y - r) * unit, width: 2 * r * unit, height: 2 * r * unit) }
    func line(_ points: [(CGFloat, CGFloat)], width: CGFloat, color: CGColor) {
        context.setStrokeColor(color)
        context.setLineWidth(width * unit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addLines(between: points.map { p($0.0, $0.1) })
        context.strokePath()
    }
    func cut(_ draw: () -> Void) {
        context.saveGState()
        context.setBlendMode(.clear)
        draw()
        context.restoreGState()
    }
    let body = template ? black : terracotta
    let shade = template ? black : terracottaDark
    for side: CGFloat in [-1, 1] {
        func x(_ value: CGFloat) -> CGFloat { 50 + side * value }
        for (start, end) in [((24, 38), (38, 30)), ((22, 32), (35, 22)), ((18, 28), (29, 16))] as [((CGFloat, CGFloat), (CGFloat, CGFloat))] {
            line([(x(start.0), start.1), (x(start.0 + 8), end.1 + 6), (x(end.0), end.1)], width: 5, color: shade)
        }
        line([(x(22), 50), (x(30), 60), (x(33), 66)], width: 7, color: shade)
        line([(x(18), 52), (x(24), 58)], width: 7, color: shade)
        context.setFillColor(body)
        context.fillEllipse(in: circle(x(34), 70, 11))
        let notch = { (color: CGColor) in
            context.setFillColor(color)
            context.move(to: p(x(34), 70))
            context.addLine(to: p(x(28), 84))
            context.addLine(to: p(x(40), 84))
            context.closePath()
            context.fillPath()
        }
        if template { cut { notch(black) } } else { notch(cream) }
        line([(x(9), 50), (x(9), 60)], width: 4, color: shade)
    }
    let shell = CGRect(x: rect.minX + 19 * unit, y: rect.minY + 22 * unit, width: 62 * unit, height: 38 * unit)
    context.setFillColor(shade)
    context.fillEllipse(in: shell.offsetBy(dx: 0, dy: -3 * unit))
    context.setFillColor(body)
    context.fillEllipse(in: shell)
    for side: CGFloat in [-1, 1] {
        line([(50 + side * 8, 56), (50 + side * 10, 72)], width: 4, color: body)
        context.setFillColor(template ? black : white)
        context.fillEllipse(in: circle(50 + side * 10, 76, 6.5))
        if template {
            cut { context.fillEllipse(in: circle(50 + side * 10, 76, 3)) }
        } else {
            context.setStrokeColor(terracottaDark)
            context.setLineWidth(1.5 * unit)
            context.strokeEllipse(in: circle(50 + side * 10, 76, 6.5))
            context.setFillColor(ink)
            context.fillEllipse(in: circle(50 + side * 10 + 1, 75.5, 3.2))
        }
    }
    let smile = { (color: CGColor) in
        context.setStrokeColor(color)
        context.setLineWidth(3 * unit)
        context.setLineCap(.round)
        context.addArc(center: p(50, 44), radius: 7 * unit, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        context.strokePath()
    }
    if template { cut { smile(black) } } else { smile(ink) }
}

func render(_ size: Int, draw: (CGContext, CGFloat) -> Void) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context, CGFloat(size))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func appIcon(_ context: CGContext, _ size: CGFloat) {
    let square = CGRect(x: size * 100 / 1024, y: size * 100 / 1024, width: size * 824 / 1024, height: size * 824 / 1024)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: CGColor(gray: 0, alpha: 0.25))
    context.addPath(squircle(square))
    context.setFillColor(cream)
    context.fillPath()
    context.restoreGState()
    let width = square.width * 0.7 / 0.9
    crab(context, in: CGRect(x: square.midX - width / 2, y: square.midY - width * 0.52, width: width, height: width), template: false)
}

func statusIcon(_ context: CGContext, _ size: CGFloat) {
    let width = size / 0.9
    crab(context, in: CGRect(x: size / 2 - width / 2, y: size / 2 - width * 0.52, width: width, height: width), template: true)
}

let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(size, draw: appIcon).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try render(18, draw: statusIcon).write(to: output.appendingPathComponent("StatusIcon.png"))
try render(36, draw: statusIcon).write(to: output.appendingPathComponent("StatusIcon@2x.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}

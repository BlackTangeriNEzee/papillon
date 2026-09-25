import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let photo = NSImage(contentsOf: root.appendingPathComponent("mac/icon-source.png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("mac/icon-source.png could not be read\n".data(using: .utf8)!)
    exit(1)
}
guard let menu = NSImage(contentsOf: root.appendingPathComponent("mac/menubar-source.png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("mac/menubar-source.png could not be read\n".data(using: .utf8)!)
    exit(1)
}
let appCrop = photo.cropping(to: CGRect(x: 0, y: 0, width: 1254, height: 1254))!
let faceCrop = menu.cropping(to: CGRect(x: 290, y: 220, width: 660, height: 660))!

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

func render(_ size: Int, draw: (CGContext, CGFloat) -> Void) -> Data {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    draw(context, CGFloat(size))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func appIcon(_ context: CGContext, _ side: CGFloat) {
    let square = CGRect(x: side * 100 / 1024, y: side * 100 / 1024, width: side * 824 / 1024, height: side * 824 / 1024)
    let shape = squircle(square)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -side * 0.01), blur: side * 0.03, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(shape)
    context.clip()
    context.draw(appCrop, in: square)
}

func statusIcon(_ context: CGContext, _ side: CGFloat) {
    let circle = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: 0.5, dy: 0.5)
    context.saveGState()
    context.addEllipse(in: circle)
    context.clip()
    context.draw(faceCrop, in: CGRect(x: 0, y: 0, width: side, height: side))
    context.restoreGState()
    context.setStrokeColor(CGColor(gray: 0, alpha: 0.2))
    context.setLineWidth(1)
    context.strokeEllipse(in: circle)
}

let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(size, draw: appIcon).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try render(22, draw: statusIcon).write(to: output.appendingPathComponent("StatusIcon.png"))
try render(44, draw: statusIcon).write(to: output.appendingPathComponent("StatusIcon@2x.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}

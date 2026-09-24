import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let cream = CGColor(srgbRed: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEE / 255, alpha: 1)
let terracotta = CGColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)

let grid = [
    ".xxxxxxxxx.",
    ".xxxxxxxxx.",
    "xx.xxxxx.xx",
    "xxxxxxxxxxx",
    ".xxxxxxxxx.",
    ".xxxxxxxxx.",
    ".x.x...x.x.",
    ".x.x...x.x.",
]

func drawClawd(_ context: CGContext, center: CGPoint, cell: CGSize, color: CGColor) {
    let columns = grid[0].count, rows = grid.count
    let origin = CGPoint(x: (center.x - CGFloat(columns) * cell.width / 2).rounded(), y: (center.y - CGFloat(rows) * cell.height / 2).rounded())
    context.setFillColor(color)
    for (row, line) in grid.enumerated() {
        for (column, character) in line.enumerated() where character == "x" {
            context.fill(CGRect(x: origin.x + CGFloat(column) * cell.width, y: origin.y + CGFloat(rows - 1 - row) * cell.height, width: cell.width, height: cell.height))
        }
    }
}

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

func render(_ width: Int, _ height: Int, draw: (CGContext) -> Void) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setShouldAntialias(false)
    draw(context)
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func appIcon(_ size: Int) -> Data {
    render(size, size) { context in
        let side = CGFloat(size)
        let square = CGRect(x: side * 100 / 1024, y: side * 100 / 1024, width: side * 824 / 1024, height: side * 824 / 1024)
        context.saveGState()
        context.setShouldAntialias(true)
        context.setShadow(offset: CGSize(width: 0, height: -side * 0.01), blur: side * 0.03, color: CGColor(gray: 0, alpha: 0.25))
        context.addPath(squircle(square))
        context.setFillColor(cream)
        context.fillPath()
        context.restoreGState()
        let exact = square.width * 0.7 / CGFloat(grid[0].count)
        let width = exact >= 2 ? exact.rounded(.down) : exact
        let height = exact >= 2 ? (width * 1.1).rounded() : width * 1.1
        drawClawd(context, center: CGPoint(x: square.midX, y: square.midY), cell: CGSize(width: width, height: height), color: terracotta)
    }
}

let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, size) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try appIcon(size).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
let statusCell = CGSize(width: 3, height: 4)
try render(grid[0].count * Int(statusCell.width), grid.count * Int(statusCell.height)) { context in
    drawClawd(context, center: CGPoint(x: CGFloat(grid[0].count) * statusCell.width / 2, y: CGFloat(grid.count) * statusCell.height / 2), cell: statusCell, color: CGColor(gray: 0, alpha: 1))
}.write(to: output.appendingPathComponent("StatusIcon@2x.png"))
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}

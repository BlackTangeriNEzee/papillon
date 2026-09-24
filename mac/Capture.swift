import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

final class KeyPanel: NSPanel {
    var onCancel: () -> Void = {}

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onCancel() }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class SelectionView: NSView {
    var finish: (NSRect?) -> Void = { _ in }
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .mouseMoved, .activeAlways], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseMoved(with event: NSEvent) { NSCursor.crosshair.set() }

    private var scale: CGFloat { window?.backingScaleFactor ?? 1 }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        let rect = NSRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x - current.x), height: abs(start.y - current.y))
        return backingAlignedRect(rect, options: .alignAllEdgesNearest)
    }

    private func point(_ event: NSEvent) -> NSPoint {
        let point = convert(event.locationInWindow, from: nil)
        return NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    override func mouseDown(with event: NSEvent) {
        start = point(event)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = point(event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = point(event)
        let rect = selection
        start = nil
        current = nil
        needsDisplay = true
        guard let rect, rect.width * scale >= 8, rect.height * scale >= 8 else { return finish(nil) }
        finish(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { finish(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let rect = selection, rect.width > 0, rect.height > 0 else { return }
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        Theme.accent.ns.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        border.stroke()
        for corner in [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)] {
            let handle = NSRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8)
            Theme.accent.ns.setFill()
            handle.fill()
            NSColor.white.setStroke()
            NSBezierPath(rect: handle.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        let label = NSAttributedString(string: "\(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded())) px", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white])
        let size = label.size()
        var box = NSRect(x: rect.minX, y: rect.maxY + 8, width: size.width + 12, height: size.height + 6)
        if box.maxY > bounds.maxY { box.origin.y = rect.maxY - box.height - 8 }
        box.origin.x = min(max(box.minX, bounds.minX), bounds.maxX - box.width)
        Theme.accent.ns.setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3))
    }
}

struct Block: Identifiable {
    let id: Int
    let rect: CGRect
    let text: String
    let lineHeight: CGFloat
    let background: NSColor
    var result: Load<Translated> = .loading

    var foreground: NSColor {
        let color = background.usingColorSpace(.sRGB) ?? .white
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent > 0.55 ? .black : .white
    }

    func layout(_ text: String, limit: CGSize) -> (rect: CGRect, fontSize: CGFloat) {
        let pad = max(2, lineHeight * 0.15)
        var rect = self.rect.insetBy(dx: -pad, dy: -pad)
        let width = rect.width - 4
        func height(_ size: CGFloat) -> CGFloat {
            ceil((text as NSString).boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: size)]).height)
        }
        var size = max(9, (lineHeight * 0.7).rounded())
        while size > 9 && height(size) > rect.height { size -= 0.5 }
        rect.size.height = max(rect.height, height(size))
        rect.origin.y = min(rect.minY, max(0, limit.height - rect.height))
        return (rect, size)
    }
}

enum Blocks {
    static func make(_ lines: [TextLine], image: CGImage, size: CGSize) -> [Block] {
        let rects = lines.map { CGRect(x: $0.box.minX * size.width, y: (1 - $0.box.maxY) * size.height, width: $0.box.width * size.width, height: $0.box.height * size.height) }
        var groups: [[Int]] = []
        for index in rects.indices.sorted(by: { rects[$0].minY < rects[$1].minY }) {
            let line = rects[index]
            let match = groups.lastIndex { group in
                let last = rects[group.last!]
                let union = group.map { rects[$0] }.reduce(last) { $0.union($1) }
                let gap = line.minY - last.maxY
                let small = min(line.height, last.height)
                return gap < 0.6 * small && gap > -0.5 * small && max(line.height, last.height) < 1.6 * small && line.minX < union.maxX && line.maxX > union.minX
            }
            if let match { groups[match].append(index) } else { groups.append([index]) }
        }
        let pixels = Pixels(image)
        let scale = CGFloat(image.width) / size.width
        let boxes: [(lines: [Int], rect: CGRect)] = groups.map { group in (group, group.map { rects[$0] }.reduce(rects[group[0]]) { $0.union($1) }) }
        let ordered = boxes.sorted { a, b in abs(a.rect.minY - b.rect.minY) < 4 ? a.rect.minX < b.rect.minX : a.rect.minY < b.rect.minY }
        return ordered.enumerated().map { offset, box in
            let lineHeight = box.lines.map { rects[$0].height }.reduce(0, +) / CGFloat(box.lines.count)
            let ring = box.rect.insetBy(dx: lineHeight * 0.15, dy: lineHeight * 0.15)
            let background = pixels?.edgeColor(CGRect(x: ring.minX * scale, y: ring.minY * scale, width: ring.width * scale, height: ring.height * scale)) ?? Theme.background.ns
            return Block(id: offset, rect: box.rect, text: OCR.join(box.lines.map { lines[$0].text }, separator: " "), lineHeight: lineHeight, background: background)
        }
    }
}

struct Pixels {
    let width: Int
    let height: Int
    let data: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        self.data = data
    }

    func edgeColor(_ rect: CGRect) -> NSColor? {
        let minX = max(0, Int(rect.minX)), maxX = min(width - 1, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(height - 1, Int(rect.maxY))
        guard minX < maxX, minY < maxY else { return nil }
        var points: [(Int, Int)] = []
        for x in stride(from: minX, through: maxX, by: 2) { points += [(x, minY), (x, maxY)] }
        for y in stride(from: minY, through: maxY, by: 2) { points += [(minX, y), (maxX, y)] }
        let median = (0..<3).map { channel in
            CGFloat(points.map { data[($0.1 * width + $0.0) * 4 + channel] }.sorted()[points.count / 2]) / 255
        }
        return NSColor(srgbRed: median[0], green: median[1], blue: median[2], alpha: 1)
    }
}

@MainActor
final class Pin: ObservableObject {
    @Published var note: Note?
    @Published var blocks: [Block] = []
    @Published var showOriginal = false

    var translations: [String] {
        blocks.compactMap { if case .done(let translated) = $0.result { translated.text } else { nil } }
    }

    func run(_ image: CGImage, size: CGSize) async {
        note = Note(text: L("识别中…", "Recognising text…"))
        let lines: [TextLine]
        do {
            lines = try await OCR.lines(image)
        } catch {
            note = Note(text: L("识别失败：", "OCR failed: ") + error.localizedDescription, isError: true)
            return
        }
        guard !lines.isEmpty else {
            note = Note(text: L("没有识别出文字", "No text found in the image"), isError: true)
            return
        }
        note = nil
        blocks = Blocks.make(lines, image: image, size: size)
        let texts = blocks.map(\.text)
        await withTaskGroup(of: (Int, Load<Translated>).self) { group in
            var next = 0
            while next < min(3, texts.count) {
                let index = next
                group.addTask { (index, await load { try await Translator.text(texts[index]) }) }
                next += 1
            }
            for await (index, result) in group {
                blocks[index].result = result
                if next < texts.count {
                    let index = next
                    group.addTask { (index, await load { try await Translator.text(texts[index]) }) }
                    next += 1
                }
            }
        }
    }
}

struct PinView: View {
    let image: NSImage?
    let width: CGFloat
    @ObservedObject var pin: Pin
    let close: () -> Void
    let drag: (CGSize?) -> Void
    let resize: (CGFloat) -> Void
    @State private var hovering = false

    private var working: Bool {
        (pin.note != nil && pin.note?.isError == false) || pin.blocks.contains { if case .loading = $0.result { true } else { false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: image)
                    if !pin.showOriginal {
                        ForEach(pin.blocks) { block in overlay(block, limit: image.size) }
                    }
                }
                .frame(width: image.size.width, height: image.size.height, alignment: .topLeading)
                .clipped()
                .gesture(DragGesture(minimumDistance: 3).onChanged { drag($0.translation) }.onEnded { _ in drag(nil) })
                .overlay(alignment: .topTrailing) {
                    if hovering { toolbar } else if working { ProgressView().controlSize(.mini).padding(4) }
                }
            }
            if let note = pin.note, note.isError || image == nil {
                HStack(alignment: .top, spacing: 6) {
                    NoteView(note: note).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if image == nil { toolbar }
                }
                .padding(6)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .background(Theme.surface.color)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(2)
        .background(Theme.accent.color, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: resize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func overlay(_ block: Block, limit: CGSize) -> some View {
        switch block.result {
        case .loading: EmptyView()
        case .done(let translated): box(block, text: translated.text, color: Color(nsColor: block.foreground), limit: limit)
        case .failed(let message): box(block, text: message, color: .red, limit: limit)
        }
    }

    private func box(_ block: Block, text: String, color: Color, limit: CGSize) -> some View {
        let layout = block.layout(text, limit: limit)
        return Text(text)
            .font(.system(size: layout.fontSize))
            .foregroundStyle(color)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 2)
            .frame(width: layout.rect.width, height: layout.rect.height, alignment: .leading)
            .background(Color(nsColor: block.background), in: RoundedRectangle(cornerRadius: 3))
            .offset(x: layout.rect.minX, y: layout.rect.minY)
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            if working { ProgressView().controlSize(.mini).padding(.horizontal, 3) }
            if let route = pin.blocks.lazy.compactMap({ if case .done(let translated) = $0.result { translated.route } else { nil } }).first {
                Text(route).font(.caption2.weight(.medium)).foregroundStyle(Theme.accent.color).padding(.horizontal, 3)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pin.translations.joined(separator: "\n"), forType: .string)
            } label: { Label(L("复制", "Copy"), systemImage: "doc.on.doc") }
            .help(L("复制", "Copy"))
            .disabled(pin.translations.isEmpty)
            Button { pin.showOriginal.toggle() } label: { Label(L("原文", "Original"), systemImage: pin.showOriginal ? "character.bubble.fill" : "character.bubble") }
                .help(L("原文", "Original"))
                .disabled(pin.blocks.isEmpty)
            Button(action: close) { Label(L("关闭", "Close"), systemImage: "xmark") }
                .help(L("关闭", "Close"))
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text.color)
        .controlSize(.small)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surface.color, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border.color))
        .padding(4)
        .focusEffectDisabled()
    }
}

@MainActor
final class ScreenTranslator {
    var onEscapeNeeded: (Bool) -> Void = { _ in }
    private var overlays: [KeyPanel] = [] {
        didSet { updateEscape(oldValue.isEmpty && pins.isEmpty) }
    }
    private var pins: [KeyPanel] = [] {
        didSet { updateEscape(overlays.isEmpty && oldValue.isEmpty) }
    }

    private func updateEscape(_ wasIdle: Bool) {
        let idle = overlays.isEmpty && pins.isEmpty
        if idle != wasIdle { onEscapeNeeded(!idle) }
    }

    func escape() {
        if overlays.isEmpty {
            let closing = pins
            pins = []
            closing.forEach { $0.orderOut(nil) }
            DispatchQueue.main.async { closing.forEach { $0.close() } }
        } else {
            finish(nil)
        }
    }

    func start() {
        guard overlays.isEmpty else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
            let pin = Pin()
            pin.note = Note(text: L("没有截图权限：请在“系统设置 > 隐私与安全性 > 屏幕与系统录音”中打开 Mini Dict，然后重新打开本应用", "Screen Recording permission is missing: turn on Mini Dict in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app"), isError: true)
            show(pin, image: nil, topLeft: NSPoint(x: screen.visibleFrame.midX - 180, y: screen.visibleFrame.midY + 60), screen: screen)
            return
        }
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let panel = KeyPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.finish = { [weak self, weak panel] rect in
                guard let self, let panel else { return }
                self.finish(rect.map { (panel.convertToScreen($0), screen) })
            }
            panel.onCancel = { [weak self] in self?.finish(nil) }
            panel.contentView = view
            overlays.append(panel)
            panel.orderFrontRegardless()
            if NSMouseInRect(mouse, screen.frame, false) {
                panel.makeKey()
                panel.makeFirstResponder(view)
            }
        }
    }

    private func finish(_ selection: (rect: NSRect, screen: NSScreen)?) {
        let closing = overlays
        overlays = []
        closing.forEach { $0.orderOut(nil) }
        guard let (rect, screen) = selection else { return DispatchQueue.main.async { closing.forEach { $0.close() } } }
        let pin = Pin()
        Task {
            do {
                let image = try await Self.capture(rect, screen: screen, excluding: closing.map { CGWindowID($0.windowNumber) })
                closing.forEach { $0.close() }
                show(pin, image: NSImage(cgImage: image, size: rect.size), topLeft: NSPoint(x: rect.minX, y: rect.maxY), screen: screen)
                await pin.run(image, size: rect.size)
            } catch {
                closing.forEach { $0.close() }
                pin.note = Note(text: L("截图失败：", "Screenshot failed: ") + error.localizedDescription, isError: true)
                show(pin, image: nil, topLeft: NSPoint(x: rect.minX, y: rect.maxY), screen: screen)
            }
        }
    }

    static func capture(_ rect: NSRect, screen: NSScreen, excluding windowIDs: [CGWindowID]) async throws -> CGImage {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw Failure(L("找不到显示器", "Display not found"))
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw Failure(L("找不到显示器", "Display not found"))
        }
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { windowIDs.contains($0.windowID) })
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
        configuration.width = Int((rect.width * screen.backingScaleFactor).rounded())
        configuration.height = Int((rect.height * screen.backingScaleFactor).rounded())
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    private func show(_ pin: Pin, image: NSImage?, topLeft: NSPoint, screen: NSScreen) {
        let width = image?.size.width ?? 360
        let panel = KeyPanel(contentRect: NSRect(x: topLeft.x - 2, y: topLeft.y + 1, width: width + 4, height: 1), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        let close = { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.orderOut(nil)
            panel.close()
            DispatchQueue.main.async { self.pins.removeAll { $0 === panel } }
        }
        panel.onCancel = close
        var anchor: (mouse: NSPoint, origin: NSPoint)?
        let drag = { [weak panel] (translation: CGSize?) in
            guard let panel else { return }
            let mouse = NSEvent.mouseLocation
            let start = anchor ?? (NSPoint(x: mouse.x - (translation?.width ?? 0), y: mouse.y + (translation?.height ?? 0)), panel.frame.origin)
            anchor = translation == nil ? nil : start
            panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        }
        let host = FirstMouseHostingView(rootView: PinView(image: image, width: width, pin: pin, close: close, drag: drag) { [weak panel] height in
            guard let panel, height > 0 else { return }
            var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - height, width: panel.frame.width, height: height)
            if frame.minY < screen.visibleFrame.minY { frame.origin.y = min(screen.visibleFrame.minY, screen.frame.maxY - height) }
            panel.setFrame(frame, display: true)
        })
        host.sizingOptions = []
        panel.contentView = host
        pins.append(panel)
        panel.orderFrontRegardless()
    }
}

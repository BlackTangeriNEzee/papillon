import AppKit
import ApplicationServices
import Carbon.HIToolbox
import SwiftUI

struct SelectView: View {
    let store: Store
    @ObservedObject var search: Search
    let openMain: () -> Void
    let resize: (CGFloat) -> Void
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(search.query.replacingOccurrences(of: "\n", with: " "))
                .font(.caption)
                .foregroundStyle(Theme.secondary.color)
                .lineLimit(1)
                .truncationMode(.tail)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    LookupPage(store: store, search: search, compact: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { contentHeight = $0 })
            }
            .frame(height: min(contentHeight, 320))
            Button(action: openMain) {
                Label(L("在主窗口打开", "Open in main window"), systemImage: "arrow.up.forward.app")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent.color)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(Theme.background.color)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.color, lineWidth: 1.5))
        .themed(background: false)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: resize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

@MainActor
final class SelectTranslator {
    var openMain: (String) -> Void = { _ in }
    var onVisibleChanged: (Bool) -> Void = { _ in }
    private let store: Store
    private let search = Search()
    private var monitors: [Any] = []
    private var downLocation = NSPoint.zero
    private var lastText = ""
    private var anchor = NSRect.zero
    private var panel: KeyPanel?
    private var button: KeyPanel?
    private(set) var visible = false {
        didSet { if visible != oldValue { onVisibleChanged(visible) } }
    }

    init(store: Store) {
        self.store = store
    }

    func apply() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        hide()
        guard store.selectTranslate else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel, event.window !== self.button else { return }
                self.hide()
            }
            return event
        }) { monitors.append(monitor) }
    }

    func hide() {
        panel?.orderOut(nil)
        button?.orderOut(nil)
        lastText = ""
        visible = false
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            downLocation = NSEvent.mouseLocation
            hide()
            return
        }
        guard NSWorkspace.shared.frontmostApplication != .current else { return }
        let mouse = NSEvent.mouseLocation
        let selecting = hypot(mouse.x - downLocation.x, mouse.y - downLocation.y) > 4 || event.clickCount >= 2
        guard selecting else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await capture(mouse: mouse)
        }
    }

    private func capture(mouse: NSPoint) async {
        var (text, rect) = Self.accessibilitySelection()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.clipboardFallback {
            text = await Self.copySelection()
            rect = nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 500, trimmed != lastText else { return }
        lastText = trimmed
        anchor = rect ?? NSRect(x: mouse.x, y: mouse.y - 4, width: 1, height: 8)
        if store.selectAuto { show(trimmed) } else { showButton(trimmed) }
    }

    private static func accessibilitySelection() -> (String, NSRect?) {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused else { return ("", nil) }
        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success, let text = value as? String else { return ("", nil) }
        var range: CFTypeRef?
        var bounds: CFTypeRef?
        var rect = CGRect.zero
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success, let range,
              AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success, let bounds,
              AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0,
              let top = NSScreen.screens.first?.frame.maxY else { return (text, nil) }
        return (text, NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height))
    }

    private static func copySelection() async -> String {
        let pasteboard = NSPasteboard.general
        let saved = (pasteboard.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
        let before = pasteboard.changeCount
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
        try? await Task.sleep(for: .milliseconds(150))
        guard pasteboard.changeCount != before else { return "" }
        let text = pasteboard.string(forType: .string) ?? ""
        pasteboard.clearContents()
        pasteboard.writeObjects(saved.map { pairs in
            let item = NSPasteboardItem()
            pairs.forEach { item.setData($0.1, forType: $0.0) }
            return item
        })
        return text
    }

    private func floatingPanel(_ frame: NSRect) -> KeyPanel {
        let panel = KeyPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]
        panel.onCancel = { [weak self] in self?.hide() }
        return panel
    }

    private func showButton(_ text: String) {
        let size = NSSize(width: 30, height: 30)
        let frame = NSRect(x: anchor.maxX + 4, y: anchor.minY - size.height - 4, width: size.width, height: size.height)
        let button = self.button ?? floatingPanel(frame)
        self.button = button
        button.contentView = FirstMouseHostingView(rootView: Button { [weak self] in self?.show(text) } label: {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.onAccent.color)
                .frame(width: 30, height: 30)
                .background(Theme.accent.color, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(L("翻译选中的文字", "Translate the selection")))
        button.setFrame(frame, display: true)
        button.orderFrontRegardless()
        visible = true
    }

    private func show(_ text: String) {
        button?.orderOut(nil)
        search.run(text)
        let panel = self.panel ?? floatingPanel(NSRect(x: anchor.minX, y: anchor.minY - 7, width: 360, height: 1))
        self.panel = panel
        let anchor = self.anchor
        let host = FirstMouseHostingView(rootView: SelectView(store: store, search: search, openMain: { [weak self] in
            self?.hide()
            self?.openMain(text)
        }) { [weak panel] height in
            guard let panel, height > 0 else { return }
            let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
            let visible = screen.visibleFrame
            let x = min(max(anchor.minX, visible.minX + 4), visible.maxX - 364)
            let below = anchor.minY - 6 - height
            let y = below >= visible.minY ? below : min(anchor.maxY + 6, visible.maxY - height)
            panel.setFrame(NSRect(x: x, y: y, width: 360, height: height), display: true)
        })
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        visible = true
    }
}

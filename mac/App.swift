import AppKit
import Carbon.HIToolbox
import SwiftUI

final class DropHostingView<Content: View>: NSHostingView<Content> {
    var onDrop: @MainActor (NSPasteboard) -> Bool = { _ in false }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { onDrop(sender.draggingPasteboard) }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = Store()
    private let quick = Search()
    private let popover = NSPopover()
    private let screenTranslator = ScreenTranslator()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusMenu = NSMenu()
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    private var hotKeys: [EventHotKeyRef] = []
    private var escapeHotKey: EventHotKeyRef?

    static func main() {
        let app = NSApplication.shared
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) { app.applicationIconImage = icon }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.takeScreenshot = { [weak self] in self?.screenshot() }
        store.openSettings = { [weak self] in self?.showSettings() }
        store.onLanguageChanged = { [weak self] in self?.setUpMenus() }
        store.onStatusItemChanged = { [weak self] in self?.statusItem.isVisible = $0 }
        store.registerShortcuts = { [weak self] in self?.registerHotKeys() ?? [] }
        store.unregisterShortcuts = { [weak self] in self?.unregisterHotKeys() }
        screenTranslator.onEscapeNeeded = { [weak self] in self?.setEscapeHotKey($0) }
        quick.onSearch = { [weak self] in self?.store.addHistory($0) }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 420)
        popover.contentViewController = NSHostingController(rootView: QuickView(store: store, search: quick) { [weak self] in self?.openQuickInMain() })
        setUpMenus()
        setUpStatusItem()
        setUpWindows()
        installHotKeyHandler()
        let errors = registerHotKeys()
        if !errors.isEmpty { showAlert(L("快捷键不可用", "Shortcut unavailable"), errors.joined(separator: "\n")) }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.store.recording == nil else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                if let client = self.window.firstResponder as? NSTextInputClient, client.hasMarkedText() { return event }
                if self.store.main.historyOpen {
                    self.store.main.historyOpen = false
                    return nil
                }
                NSApp.hide(nil)
                return nil
            }
            let pasteboard = NSPasteboard.general
            let imageFile = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: ["public.image"]])
            let textPaste = self.window.firstResponder is NSTextView && pasteboard.string(forType: .string) != nil && !imageFile
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "v", !textPaste, let image = NSImage(pasteboard: pasteboard) {
                self.store.runOcr(image)
                return nil
            }
            return event
        }
        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !store.keepRunning
    }

    func windowWillClose(_ notification: Notification) {
        guard store.recording != nil else { return }
        store.stopRecording()
        store.applyShortcuts()
    }

    private func setUpMenus() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("设置…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("隐藏 Mini Dict", "Hide Mini Dict"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: L("退出 Mini Dict", "Quit Mini Dict"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = NSMenu(title: L("编辑", "Edit"))
        edit.addItem(withTitle: L("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("拷贝", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let windowMenu = NSMenu(title: L("窗口", "Window"))
        windowMenu.addItem(withTitle: L("打开", "Open"), action: #selector(showWindow), keyEquivalent: "n")
        windowMenu.addItem(withTitle: L("最小化", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: L("关闭", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let main = NSMenu()
        for menu in [appMenu, edit, windowMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu

        statusMenu.removeAllItems()
        statusMenu.addItem(withTitle: L("打开", "Open"), action: #selector(showWindow), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: L("截图翻译", "Screenshot translate"), action: #selector(screenshot), keyEquivalent: "").target = self
        statusMenu.addItem(withTitle: L("设置", "Settings"), action: #selector(showSettings), keyEquivalent: "").target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: L("退出", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
    }

    private func setUpStatusItem() {
        statusItem.isVisible = store.showStatusItem
        guard let button = statusItem.button else { return }
        if let image = Bundle.main.image(forResource: "StatusIcon") ?? NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Mini Dict") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "词"
        }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            if NSApp.isHidden {
                window.orderOut(nil)
                NSApp.unhide(nil)
            }
            if let front = NSWorkspace.shared.frontmostApplication, front != .current {
                NSRunningApplication.current.activate(from: front)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            quick.focusRequest += 1
        }
    }

    private func openQuickInMain() {
        popover.performClose(nil)
        store.search(quick.query)
        showWindow()
    }

    private func setUpWindows() {
        let host = DropHostingView(rootView: MainView(store: store))
        host.registerForDraggedTypes([.fileURL, .png, .tiff])
        host.onDrop = { [weak self] pasteboard in
            guard let self else { return false }
            guard let image = NSImage(pasteboard: pasteboard) else {
                self.store.showOcrError(L("请拖入图片文件", "Please drop an image file"))
                return false
            }
            self.store.runOcr(image)
            return true
        }
        window.title = "Mini Dict"
        window.backgroundColor = Theme.background.ns
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentMinSize = NSSize(width: 700, height: 480)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName("SidebarWindow") { window.center() }
        window.setFrameAutosaveName("SidebarWindow")
    }

    private func installHotKeyHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.hotKeyPressed(id.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        if status != noErr { showAlert(L("快捷键不可用", "Shortcuts unavailable"), "InstallEventHandler error \(status)") }
    }

    private func unregisterHotKeys() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys = []
    }

    private func registerHotKeys() -> [String] {
        unregisterHotKeys()
        var errors: [String] = []
        for (index, shortcut) in store.shortcuts.enumerated() {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: OSType(0x4D444354), id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                hotKeys.append(ref)
            } else {
                let reason = status == OSStatus(eventHotKeyExistsErr) ? L("已被占用", "already in use") : "error \(status)"
                errors.append(L("无法注册快捷键 ", "Could not register ") + shortcut.display + " (\(reason))")
            }
        }
        return errors
    }

    private func setEscapeHotKey(_ on: Bool) {
        if let escapeHotKey { UnregisterEventHotKey(escapeHotKey) }
        escapeHotKey = nil
        guard on else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: OSType(0x4D444354), id: 100), GetApplicationEventTarget(), 0, &ref)
        if status == noErr { escapeHotKey = ref } else { NSLog("Mini Dict: could not register Esc for screenshot translation, error %d", status) }
    }

    private func hotKeyPressed(_ id: UInt32) {
        switch id {
        case 100:
            screenTranslator.escape()
        case 1:
            if NSApp.isActive && window.isKeyWindow {
                NSApp.hide(nil)
            } else {
                store.page = .lookup
                showWindow()
            }
        case 2:
            screenshot()
        default:
            translateClipboard()
        }
    }

    @objc private func showWindow() {
        NSApp.unhide(nil)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        store.main.focusRequest += 1
    }

    @objc private func showSettings() {
        store.apis = Provider.all.map(APISettings.stored)
        store.apiNotes = [:]
        store.page = .settings
        showWindow()
    }

    @objc private func screenshot() {
        screenTranslator.start()
    }

    private func translateClipboard() {
        showWindow()
        let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            store.page = .lookup
            store.main.lookup = nil
            store.main.note = Note(text: L("剪贴板里没有文字，请先按 Cmd+C 复制", "No text in the clipboard, press Cmd+C first"), isError: true)
        } else {
            store.search(text)
        }
    }

    @objc func translateService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            error.pointee = "No text was selected"
            return
        }
        showWindow()
        store.search(text)
    }

    private func showAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}

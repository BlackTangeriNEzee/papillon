import AVFoundation
import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum Page: Hashable {
    case lookup, screenshot, lists
}

enum Load<Value> {
    case loading
    case done(Value)
    case failed(String)
}

struct Note {
    let text: String
    var isError = false
}

struct Lookup {
    let id = UUID()
    let text: String
    let kind: Kind
    var translation: Load<Translation> = .loading
    var phonetic: Load<Phonetic?> = .loading
    var meanings: Load<[Meaning]?> = .loading
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var key: String

    static let defaults = [
        Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), key: "Space"),
        Shortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey), key: "S"),
        Shortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey), key: "D"),
    ]

    static let named: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab", kVK_Delete: "Delete", kVK_ForwardDelete: "⌦", kVK_Escape: "Esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags
        keyCode = UInt32(event.keyCode)
        modifiers = (flags.contains(.control) ? UInt32(controlKey) : 0) | (flags.contains(.option) ? UInt32(optionKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0) | (flags.contains(.command) ? UInt32(cmdKey) : 0)
        key = Shortcut.named[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? "#\(event.keyCode)"
    }

    var display: String {
        let symbols = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")].filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined()
        return "\(symbols) \(key)"
    }
}

func load<Value>(_ work: () async throws -> Value) async -> Load<Value> {
    do {
        return .done(try await work())
    } catch {
        return .failed(error.localizedDescription)
    }
}

func flag(_ key: String) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? true
}

@MainActor
final class Search: ObservableObject {
    @Published var query = ""
    @Published var note: Note?
    @Published var lookup: Lookup?
    @Published var focusRequest = 0
    var onSearch: (String) -> Void = { _ in }
    private var player: AVPlayer?
    private var playerStatus: NSKeyValueObservation?

    func run(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        query = text
        guard !text.isEmpty else {
            lookup = nil
            note = Note(text: L("请输入要翻译的内容", "Please enter a word, phrase or paragraph"), isError: true)
            return
        }
        note = nil
        onSearch(text)
        let kind = TextTools.kind(text)
        let current = Lookup(text: text, kind: kind)
        lookup = current
        Task {
            let result = await load {
                if kind == .paragraph {
                    let translated = try await Translator.text(text)
                    return Translation(route: translated.route, candidates: [translated.text], senses: [])
                }
                return try await Translator.search(text, isWord: kind == .word)
            }
            if lookup?.id == current.id { lookup?.translation = result }
        }
        guard kind == .word else { return }
        Task {
            let result = await load { try await WordSources.withLowercase(text, WordSources.phonetic) }
            if lookup?.id == current.id { lookup?.phonetic = result }
        }
        Task {
            let result = await load { try await WordSources.withLowercase(text, WordSources.meanings) }
            if lookup?.id == current.id { lookup?.meanings = result }
        }
    }

    func play(_ url: URL) {
        let item = AVPlayerItem(url: url)
        playerStatus = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "unknown error"
            DispatchQueue.main.async { self?.note = Note(text: L("播放失败：", "Audio failed: ") + message, isError: true) }
        }
        player = AVPlayer(playerItem: item)
        player?.play()
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var page = Page.lookup
    @Published var history = UserDefaults.standard.stringArray(forKey: "history") ?? [] {
        didSet { UserDefaults.standard.set(history, forKey: "history") }
    }
    @Published var favourites = UserDefaults.standard.stringArray(forKey: "favourites") ?? [] {
        didSet { UserDefaults.standard.set(favourites, forKey: "favourites") }
    }
    @Published var ocrImage: NSImage?
    @Published var ocrText = ""
    @Published var ocrNote: Note?
    @Published var ocrResult: Load<Translated>?
    @Published var settings = APISettings.stored()
    @Published var settingsNote: Note?
    @Published var uiLanguage = UILanguage(rawValue: UserDefaults.standard.string(forKey: "uiLanguage") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(uiLanguage.rawValue, forKey: "uiLanguage")
            onLanguageChanged()
        }
    }
    @Published var shortcuts = (UserDefaults.standard.data(forKey: "shortcuts")).flatMap { try? JSONDecoder().decode([Shortcut].self, from: $0) } ?? Shortcut.defaults {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") }
    }
    @Published var recording: Int?
    @Published var shortcutNote: Note?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var systemNote: Note?
    @Published var showStatusItem = flag("showStatusItem") {
        didSet {
            UserDefaults.standard.set(showStatusItem, forKey: "showStatusItem")
            onStatusItemChanged(showStatusItem)
        }
    }
    @Published var keepRunning = flag("keepRunning") {
        didSet { UserDefaults.standard.set(keepRunning, forKey: "keepRunning") }
    }
    var takeScreenshot: () -> Void = {}
    var openSettings: () -> Void = {}
    var onLanguageChanged: () -> Void = {}
    var onStatusItemChanged: (Bool) -> Void = { _ in }
    var registerShortcuts: () -> [String] = { [] }
    var unregisterShortcuts: () -> Void = {}
    let main = Search()
    private var ocrId = 0
    private var recorder: Any?

    init() {
        main.onSearch = { [unowned self] in addHistory($0) }
    }

    func search(_ raw: String) {
        page = .lookup
        main.run(raw)
    }

    func addHistory(_ text: String) {
        history = Array(([text] + history.filter { $0 != text }).prefix(20))
    }

    func toggleFavourite(_ text: String) {
        favourites = favourites.contains(text) ? favourites.filter { $0 != text } : [text] + favourites
    }

    func showOcrError(_ message: String) {
        page = .screenshot
        ocrNote = Note(text: message, isError: true)
    }

    func runOcr(_ image: NSImage) {
        ocrId += 1
        let id = ocrId
        page = .screenshot
        ocrImage = image
        ocrText = ""
        ocrResult = nil
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            ocrNote = Note(text: L("识别失败：无法读取图片", "OCR failed: the image could not be read"), isError: true)
            return
        }
        ocrNote = Note(text: L("识别中…", "Recognising text…"))
        Task {
            do {
                let text = try await OCR.recognize(cgImage)
                guard id == ocrId else { return }
                ocrText = text
                ocrNote = text.isEmpty ? Note(text: L("没有识别出文字", "No text found in the image"), isError: true) : Note(text: L("识别完成", "OCR done"))
            } catch {
                if id == ocrId { ocrNote = Note(text: L("识别失败：", "OCR failed: ") + error.localizedDescription, isError: true) }
            }
        }
    }

    func translateOcr() {
        let text = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            ocrResult = .failed(L("没有可翻译的文字", "Nothing to translate"))
            return
        }
        ocrResult = .loading
        Task { ocrResult = await load { try await Translator.text(text) } }
    }

    private var trimmedSettings: APISettings {
        APISettings(base: settings.base.trimmingCharacters(in: .whitespacesAndNewlines), key: settings.key.trimmingCharacters(in: .whitespacesAndNewlines), model: settings.model.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func saveSettings() {
        settings = trimmedSettings
        settings.save()
        settingsNote = Note(text: APISettings.active() == nil ? L("已保存，但未填全，将使用免费翻译", "Saved, but not all fields are filled, so the free route is used") : L("已保存，将使用 API", "Saved, the API will be used"))
    }

    func clearSettings() {
        settings = APISettings()
        settings.save()
        settingsNote = Note(text: L("已清除，将使用免费翻译", "Cleared, the free route is used"))
    }

    func testSettings() {
        let api = trimmedSettings
        guard !api.base.isEmpty, !api.key.isEmpty, !api.model.isEmpty else {
            settingsNote = Note(text: L("请先填写三项", "Fill in all three fields first"), isError: true)
            return
        }
        settingsNote = Note(text: L("测试中…", "Testing…"))
        Task {
            do {
                let reply = try await Translator.callApi(api, system: "Translate the user's text into Simplified Chinese. Reply with the translation only.", text: "hello")
                settingsNote = Note(text: L("测试成功：", "Test passed: ") + reply)
            } catch {
                settingsNote = Note(text: error.localizedDescription, isError: true)
            }
        }
    }

    func applyShortcuts() {
        let errors = registerShortcuts()
        shortcutNote = errors.isEmpty ? nil : Note(text: errors.joined(separator: "\n"), isError: true)
    }

    func startRecording(_ index: Int) {
        stopRecording()
        unregisterShortcuts()
        recording = index
        shortcutNote = Note(text: L("请按下新的组合键，按 Esc 取消", "Press the new key combination, or Esc to cancel"))
        let window = NSApp.keyWindow
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === window else { return event }
            self?.record(event)
            return nil
        }
    }

    private func record(_ event: NSEvent) {
        guard let index = recording else { return }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Escape) && flags.isEmpty {
            stopRecording()
            applyShortcuts()
            return
        }
        guard !flags.isDisjoint(with: [.command, .option, .control]) else {
            shortcutNote = Note(text: L("快捷键必须包含 ⌘、⌥ 或 ⌃，请重新按下", "A shortcut needs ⌘, ⌥ or ⌃. Press another combination"), isError: true)
            return
        }
        shortcuts[index] = Shortcut(event: event)
        stopRecording()
        applyShortcuts()
    }

    func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        recording = nil
    }

    func resetShortcuts() {
        stopRecording()
        shortcuts = Shortcut.defaults
        applyShortcuts()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            systemNote = SMAppService.mainApp.status == .requiresApproval ? Note(text: L("需要在“系统设置 > 通用 > 登录项”中允许", "Allow it in System Settings > General > Login Items"), isError: true) : nil
        } catch {
            systemNote = Note(text: L("开机启动设置失败：", "Launch at login failed: ") + error.localizedDescription, isError: true)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

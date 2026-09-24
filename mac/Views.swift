import SwiftUI

struct InputView: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onSubmit: () -> Void
    static let font = NSFont.systemFont(ofSize: 15)
    static let inset = NSSize(width: 6, height: 7)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = InputView.font
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = InputView.inset
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text { textView.string = text }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.selectAll(nil)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        let sample = text.isEmpty || text.hasSuffix("\n") ? text + "x" : text
        let bounds = (sample as NSString).boundingRect(with: NSSize(width: width - 2 * InputView.inset.width - 10, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: InputView.font])
        let line = NSLayoutManager().defaultLineHeight(for: InputView.font)
        return CGSize(width: width, height: min(max(bounds.height, 3 * line), 8 * line) + 2 * InputView.inset.height)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputView
        var focusRequest = -1

        init(_ parent: InputView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }
    }
}

struct MainView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 10) {
                Picker("", selection: $store.page) {
                    Text(L("查词", "Lookup")).tag(Page.lookup)
                    Text(L("截图", "Screenshot")).tag(Page.screenshot)
                    Text(L("历史", "History")).tag(Page.lists)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                if store.page == .lookup {
                    InputView(text: $store.query, focusRequest: store.focusRequest) { store.search(store.query) }
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.35)))
                        .overlay(alignment: .topLeading) {
                            if store.query.isEmpty {
                                Text(L("输入单词、短语或段落，回车翻译，Shift+回车换行", "Type a word, phrase or paragraph. Enter translates, Shift+Enter adds a line"))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button(L("翻译", "Translate")) { store.search(store.query) }.buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch store.page {
                    case .lookup: LookupPage(store: store)
                    case .screenshot: ScreenshotPage(store: store)
                    case .lists: ListsPage(store: store)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

struct LookupPage: View {
    @ObservedObject var store: Store

    var body: some View {
        if let note = store.note { NoteView(note: note) }
        if let lookup = store.lookup {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if lookup.kind != .paragraph { Text(lookup.text).font(.title2.weight(.semibold)).textSelection(.enabled) }
                if case .done(let translation) = lookup.translation { RouteTag(route: translation.route) }
                Spacer()
                let on = store.favourites.contains(lookup.text)
                Button { store.toggleFavourite(lookup.text) } label: {
                    Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(on ? L("取消收藏", "Remove favourite") : L("收藏", "Add favourite"))
            }
            if lookup.kind == .word { PhoneticView(store: store, phonetic: lookup.phonetic) }
            switch lookup.translation {
            case .loading: Progress(text: L("翻译中…", "Translating…"))
            case .failed(let message): NoteView(note: Note(text: message, isError: true))
            case .done(let translation):
                if translation.candidates.isEmpty {
                    NoteView(note: Note(text: L("未找到翻译", "No translation found"), isError: true))
                } else if lookup.kind == .paragraph {
                    Text(translation.candidates[0]).font(.title3).lineSpacing(4).textSelection(.enabled)
                } else {
                    Numbered(items: translation.candidates, font: .title3)
                }
                if translation.route == Translator.free && TextTools.isSentence(lookup.text) { FreeHint(store: store) }
                if !translation.senses.isEmpty {
                    Heading(text: L("释义", "Senses"))
                    Numbered(items: translation.senses)
                }
            }
            if lookup.kind == .word {
                Divider()
                switch lookup.meanings {
                case .loading: Progress(text: L("词典加载中…", "Loading dictionary…"))
                case .failed(let message): NoteView(note: Note(text: L("词典暂不可用", "Dictionary entry unavailable") + " (\(message))"))
                case .done(nil): NoteView(note: Note(text: L("词典中未找到该词", "Word not found in dictionary"), isError: true))
                case .done(let meanings?):
                    ForEach(meanings, id: \.self) { meaning in
                        Heading(text: meaning.partOfSpeech)
                        ForEach(Array(meaning.definitions.enumerated()), id: \.offset) { index, definition in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(definition.text)
                                    if !definition.example.isEmpty {
                                        Text(L("例：", "e.g. ") + definition.example).foregroundStyle(.secondary).italic()
                                    }
                                }
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct PhoneticView: View {
    let store: Store
    let phonetic: Load<Phonetic?>

    var body: some View {
        switch phonetic {
        case .loading: EmptyView()
        case .failed(let message): NoteView(note: Note(text: L("音标暂不可用", "Phonetic unavailable") + " (\(message))"))
        case .done(nil): NoteView(note: Note(text: L("音标暂不可用（未找到）", "Phonetic unavailable (not found)")))
        case .done(let value?):
            HStack(spacing: 10) {
                if let ipa = value.ipa { Text(ipa).foregroundStyle(.secondary).textSelection(.enabled) }
                if let audio = value.audio {
                    Button { store.play(audio) } label: { Label(L("发音", "Play"), systemImage: "speaker.wave.2") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

struct ScreenshotPage: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 10) {
            Button { store.takeScreenshot() } label: { Label(L("截图", "Take screenshot"), systemImage: "camera.viewfinder") }
                .buttonStyle(.borderedProminent)
            Text(store.shortcuts[1].display).foregroundStyle(.secondary)
        }
        Text(L("也可以按 Cmd+V 粘贴图片，或把图片拖进窗口", "You can also paste an image with Cmd+V or drop one onto the window")).font(.callout).foregroundStyle(.secondary)
        if let image = store.ocrImage {
            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 6))
        }
        if let note = store.ocrNote { NoteView(note: note) }
        if store.ocrImage != nil || !store.ocrText.isEmpty {
            TextEditor(text: $store.ocrText)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Button(L("翻译", "Translate")) { store.translateOcr() }.buttonStyle(.borderedProminent)
        }
        switch store.ocrResult {
        case nil: EmptyView()
        case .loading: Progress(text: L("翻译中…", "Translating…"))
        case .failed(let message): NoteView(note: Note(text: message, isError: true))
        case .done(let result):
            RouteTag(route: result.route)
            Text(result.text).font(.title3).lineSpacing(4).textSelection(.enabled)
            if result.route == Translator.free { FreeHint(store: store) }
        }
    }
}

struct ListsPage: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack {
            Heading(text: L("历史", "History"))
            Spacer()
            Button(L("清空历史", "Clear history")) { store.history = [] }.controlSize(.small)
        }
        Chips(store: store, items: store.history)
        Heading(text: L("收藏", "Favourites"))
        Chips(store: store, items: store.favourites)
    }
}

struct Chips: View {
    let store: Store
    let items: [String]

    var body: some View {
        if items.isEmpty {
            Text(L("暂无", "None yet")).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) { store.search(item) }.lineLimit(1).help(item)
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store

    var body: some View {
        TabView {
            shortcuts.tabItem { Text(L("快捷键", "Shortcuts")) }
            language.tabItem { Text(L("语言", "Language")) }
            system.tabItem { Text(L("系统", "System")) }
            api.tabItem { Text("API") }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 380)
    }

    private var shortcuts: some View {
        Form {
            ForEach(0..<3, id: \.self) { index in
                LabeledContent([L("显示/隐藏窗口", "Show/hide window"), L("截图翻译", "Screenshot translate"), L("翻译剪贴板", "Translate clipboard")][index]) {
                    Button { store.startRecording(index) } label: {
                        Text(store.recording == index ? L("请按键…", "Press keys…") : store.shortcuts[index].display).frame(minWidth: 110)
                    }
                }
            }
            Button(L("重置", "Reset")) { store.resetShortcuts() }
            if let note = store.shortcutNote { NoteView(note: note) }
        }
    }

    private var language: some View {
        Form {
            Picker(L("界面语言", "Interface language"), selection: $store.uiLanguage) {
                Text("中文").tag(UILanguage.zh)
                Text("English").tag(UILanguage.en)
                Text(L("跟随系统", "System")).tag(UILanguage.system)
            }
            .pickerStyle(.radioGroup)
            Text(L("中文输入翻译成英文，其他输入翻译成简体中文。", "Chinese input is translated to English, anything else to Simplified Chinese."))
                .foregroundStyle(.secondary)
        }
    }

    private var system: some View {
        Form {
            Toggle(L("开机启动", "Launch at login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            Toggle(L("显示菜单栏图标", "Show menu bar icon"), isOn: $store.showStatusItem)
            Toggle(L("关闭窗口时保持运行", "Keep running when the window closes"), isOn: $store.keepRunning)
            if let note = store.systemNote { NoteView(note: note) }
        }
    }

    private var api: some View {
        Form {
            Text(L("三项都填写时使用这个 API（OpenAI 兼容格式），否则使用免费翻译。", "When all three are filled, this OpenAI-compatible API is used; otherwise the free route."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(L("API 地址", "Base URL"), text: $store.settings.base, prompt: Text("https://api.openai.com/v1"))
            SecureField(L("API 密钥", "Key"), text: $store.settings.key)
            TextField(L("模型", "Model"), text: $store.settings.model, prompt: Text("gpt-4o-mini"))
            HStack {
                Button(L("保存", "Save")) { store.saveSettings() }.buttonStyle(.borderedProminent)
                Button(L("测试", "Test")) { store.testSettings() }
                Button(L("清除", "Clear")) { store.clearSettings() }
            }
            if let note = store.settingsNote { NoteView(note: note) }
        }
    }
}

struct FreeHint: View {
    let store: Store

    var body: some View {
        Button(L("免费翻译较生硬，在设置中填入 API 可获得更自然的译文", "Free translation is literal; add an API in Settings for natural results")) { store.openSettings() }
            .buttonStyle(.link)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct Numbered: View {
    let items: [String]
    var font = Font.body

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                Text(item).font(font).textSelection(.enabled)
            }
        }
    }
}

struct Heading: View {
    let text: String

    var body: some View {
        Text(text).font(.headline).padding(.top, 4)
    }
}

struct RouteTag: View {
    let route: String

    var body: some View {
        Text(route)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

struct NoteView: View {
    let note: Note

    var body: some View {
        Text(note.text).foregroundStyle(note.isError ? Color.red : Color.secondary).textSelection(.enabled)
    }
}

struct Progress: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

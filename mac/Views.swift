import SwiftUI

struct InputView: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onSubmit: () -> Void
    static let font = NSFont.systemFont(ofSize: 15)
    static let inset = NSSize(width: 10, height: 10)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = InputView.font
        textView.textColor = Theme.text.ns
        textView.insertionPointColor = Theme.accent.ns
        textView.selectedTextAttributes = [.backgroundColor: Theme.accent.ns.withAlphaComponent(0.25)]
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
        return CGSize(width: width, height: min(max(bounds.height, 2 * line), 8 * line) + 2 * InputView.inset.height)
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
        VStack(spacing: 14) {
            Pills(selection: $store.page, options: [(Page.lookup, L("查词", "Lookup")), (Page.screenshot, L("截图", "Screenshot")), (Page.lists, L("历史", "History"))])
                .padding(.top, 14)
            if store.page == .lookup {
                SearchInput(search: store.main) { store.search(store.main.query) }
                    .padding(.horizontal, 16)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch store.page {
                    case .lookup: LookupPage(store: store, search: store.main)
                    case .screenshot: ScreenshotPage(store: store)
                    case .lists: ListsPage(store: store)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .themed()
    }
}

struct SearchInput: View {
    @ObservedObject var search: Search
    let submit: () -> Void

    var body: some View {
        InputView(text: $search.query, focusRequest: search.focusRequest, onSubmit: submit)
            .padding(.bottom, 34)
            .overlay(alignment: .topLeading) {
                if search.query.isEmpty {
                    Text(L("输入单词、短语或段落，回车翻译，Shift+回车换行", "Type a word, phrase or paragraph. Enter translates, Shift+Enter adds a line"))
                        .foregroundStyle(Theme.secondary.color)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.onAccent.color)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent.color, in: Circle())
                }
                .buttonStyle(.plain)
                .help(L("翻译", "Translate"))
                .accessibilityLabel(L("翻译", "Translate"))
                .padding(10)
            }
            .background(Theme.surface.color, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.border.color))
    }
}

struct QuickView: View {
    @ObservedObject var store: Store
    let search: Search
    let openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchInput(search: search) { search.run(search.query) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    LookupPage(store: store, search: search)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: openMain) {
                Label(L("在主窗口打开", "Open in main window"), systemImage: "arrow.up.forward.app")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.accent.color)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 360, height: 420)
        .themed()
    }
}

struct LookupPage: View {
    @ObservedObject var store: Store
    @ObservedObject var search: Search

    var body: some View {
        if let note = search.note { NoteView(note: note) }
        if let lookup = search.lookup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if lookup.kind != .paragraph { Text(lookup.text).font(.system(.title, design: .serif)).textSelection(.enabled) }
                    if case .done(let translation) = lookup.translation { RouteTag(route: translation.route) }
                    Spacer()
                    let on = store.favourites.contains(lookup.text)
                    Button { store.toggleFavourite(lookup.text) } label: {
                        Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Theme.accent.color : Theme.secondary.color)
                    }
                    .buttonStyle(.plain)
                    .help(on ? L("取消收藏", "Remove favourite") : L("收藏", "Add favourite"))
                }
                if lookup.kind == .word { PhoneticView(search: search, phonetic: lookup.phonetic) }
                switch lookup.translation {
                case .loading: Progress(text: L("翻译中…", "Translating…"))
                case .failed(let message): NoteView(note: Note(text: message, isError: true))
                case .done(let translation):
                    if translation.candidates.isEmpty {
                        NoteView(note: Note(text: L("未找到翻译", "No translation found"), isError: true))
                    } else if lookup.kind == .paragraph {
                        Text(translation.candidates[0]).font(.title3).lineSpacing(5).textSelection(.enabled)
                    } else {
                        Numbered(items: translation.candidates, font: .title3)
                    }
                    if translation.route == Translator.free && TextTools.isSentence(lookup.text) { FreeHint(store: store) }
                    if !translation.senses.isEmpty {
                        Heading(text: L("释义", "Senses"))
                        Numbered(items: translation.senses)
                    }
                }
            }
            .card()
            if lookup.kind == .word {
                switch lookup.meanings {
                case .loading: Progress(text: L("词典加载中…", "Loading dictionary…"))
                case .failed(let message): NoteView(note: Note(text: L("词典暂不可用", "Dictionary entry unavailable") + " (\(message))"))
                case .done(nil): NoteView(note: Note(text: L("词典中未找到该词", "Word not found in dictionary"), isError: true))
                case .done(let meanings?):
                    ForEach(meanings, id: \.self) { meaning in
                        VStack(alignment: .leading, spacing: 8) {
                            Heading(text: meaning.partOfSpeech)
                            ForEach(Array(meaning.definitions.enumerated()), id: \.offset) { index, definition in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(index + 1).").foregroundStyle(Theme.secondary.color).monospacedDigit()
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(definition.text).lineSpacing(2)
                                        if !definition.example.isEmpty {
                                            Text(L("例：", "e.g. ") + definition.example).foregroundStyle(Theme.secondary.color).italic()
                                        }
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                        }
                        .card()
                    }
                }
            }
        }
    }
}

struct PhoneticView: View {
    let search: Search
    let phonetic: Load<Phonetic?>

    var body: some View {
        switch phonetic {
        case .loading: EmptyView()
        case .failed(let message): NoteView(note: Note(text: L("音标暂不可用", "Phonetic unavailable") + " (\(message))"))
        case .done(nil): NoteView(note: Note(text: L("音标暂不可用（未找到）", "Phonetic unavailable (not found)")))
        case .done(let value?):
            HStack(spacing: 10) {
                if let ipa = value.ipa { Text(ipa).foregroundStyle(Theme.secondary.color).textSelection(.enabled) }
                if let audio = value.audio {
                    Button { search.play(audio) } label: { Label(L("发音", "Play"), systemImage: "speaker.wave.2") }
                        .buttonStyle(PillButtonStyle(prominent: false, small: true))
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
                .buttonStyle(PillButtonStyle())
            Text(store.shortcuts[1].display).foregroundStyle(Theme.secondary.color)
        }
        Text(L("也可以按 Cmd+V 粘贴图片，或把图片拖进窗口", "You can also paste an image with Cmd+V or drop one onto the window")).font(.callout).foregroundStyle(Theme.secondary.color)
        if let image = store.ocrImage {
            Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 8)).card(padding: 8)
        }
        if let note = store.ocrNote { NoteView(note: note) }
        if store.ocrImage != nil || !store.ocrText.isEmpty {
            TextEditor(text: $store.ocrText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .card(padding: 8)
            Button(L("翻译", "Translate")) { store.translateOcr() }.buttonStyle(PillButtonStyle())
        }
        switch store.ocrResult {
        case nil: EmptyView()
        case .loading: Progress(text: L("翻译中…", "Translating…"))
        case .failed(let message): NoteView(note: Note(text: message, isError: true))
        case .done(let result):
            VStack(alignment: .leading, spacing: 10) {
                RouteTag(route: result.route)
                Text(result.text).font(.title3).lineSpacing(5).textSelection(.enabled)
                if result.route == Translator.free { FreeHint(store: store) }
            }
            .card()
        }
    }
}

struct ListsPage: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Heading(text: L("历史", "History"))
                Spacer()
                Button(L("清空历史", "Clear history")) { store.history = [] }.buttonStyle(PillButtonStyle(prominent: false, small: true))
            }
            Chips(store: store, items: store.history)
        }
        .card()
        VStack(alignment: .leading, spacing: 10) {
            Heading(text: L("收藏", "Favourites"))
            Chips(store: store, items: store.favourites)
        }
        .card()
    }
}

struct Chips: View {
    let store: Store
    let items: [String]

    var body: some View {
        if items.isEmpty {
            Text(L("暂无", "None yet")).foregroundStyle(Theme.secondary.color)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button(item) { store.search(item) }.buttonStyle(PillButtonStyle(prominent: false, small: true)).help(item)
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 14) {
            Pills(selection: $tab, options: [(0, L("快捷键", "Shortcuts")), (1, L("语言", "Language")), (2, L("系统", "System")), (3, "API")])
            VStack(alignment: .leading, spacing: 12) {
                switch tab {
                case 0: shortcuts
                case 1: language
                case 2: system
                default: api
                }
            }
            .card()
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 500, height: 400)
        .themed()
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    private var shortcuts: some View {
        Group {
            ForEach(0..<3, id: \.self) { index in
                row([L("显示/隐藏窗口", "Show/hide window"), L("截图翻译", "Screenshot translate"), L("翻译剪贴板", "Translate clipboard")][index]) {
                    Button { store.startRecording(index) } label: {
                        Text(store.recording == index ? L("请按键…", "Press keys…") : store.shortcuts[index].display).frame(minWidth: 90)
                    }
                    .buttonStyle(PillButtonStyle(prominent: store.recording == index, small: true))
                }
            }
            Button(L("重置", "Reset")) { store.resetShortcuts() }.buttonStyle(PillButtonStyle(prominent: false, small: true))
            if let note = store.shortcutNote { NoteView(note: note) }
        }
    }

    private var language: some View {
        Group {
            Text(L("界面语言", "Interface language")).font(.headline)
            Pills(selection: $store.uiLanguage, options: [(UILanguage.zh, "中文"), (UILanguage.en, "English"), (UILanguage.system, L("跟随系统", "System"))])
            Text(L("中文输入翻译成英文，其他输入翻译成简体中文。", "Chinese input is translated to English, anything else to Simplified Chinese."))
                .foregroundStyle(Theme.secondary.color)
        }
    }

    private var system: some View {
        Group {
            Toggle(L("开机启动", "Launch at login"), isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            Toggle(L("显示菜单栏图标", "Show menu bar icon"), isOn: $store.showStatusItem)
            Toggle(L("关闭窗口时保持运行", "Keep running when the window closes"), isOn: $store.keepRunning)
            if let note = store.systemNote { NoteView(note: note) }
        }
        .toggleStyle(ThemedToggleStyle())
    }

    private var api: some View {
        Group {
            Text(L("三项都填写时使用这个 API（OpenAI 兼容格式），否则使用免费翻译。", "When all three are filled, this OpenAI-compatible API is used; otherwise the free route."))
                .foregroundStyle(Theme.secondary.color)
                .fixedSize(horizontal: false, vertical: true)
            field(L("API 地址", "Base URL"), TextField("", text: $store.settings.base, prompt: Text("https://api.openai.com/v1")))
            field(L("API 密钥", "Key"), SecureField("", text: $store.settings.key))
            field(L("模型", "Model"), TextField("", text: $store.settings.model, prompt: Text("gpt-4o-mini")))
            HStack {
                Button(L("保存", "Save")) { store.saveSettings() }.buttonStyle(PillButtonStyle(small: true))
                Button(L("测试", "Test")) { store.testSettings() }.buttonStyle(PillButtonStyle(prominent: false, small: true))
                Button(L("清除", "Clear")) { store.clearSettings() }.buttonStyle(PillButtonStyle(prominent: false, small: true))
            }
            if let note = store.settingsNote { NoteView(note: note) }
        }
    }

    private func field<Field: View>(_ title: String, _ input: Field) -> some View {
        row(title) {
            input
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 280)
                .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border.color))
        }
    }
}

struct ThemedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Theme.accent.color : Theme.border.color)
                    .frame(width: 36, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(Color.white).padding(2).shadow(radius: 0.5)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "1" : "0")
    }
}

struct FreeHint: View {
    let store: Store

    var body: some View {
        Button(L("免费翻译较生硬，在设置中填入 API 可获得更自然的译文", "Free translation is literal; add an API in Settings for natural results")) { store.openSettings() }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Theme.accent.color)
    }
}

struct Numbered: View {
    let items: [String]
    var font = Font.body

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index + 1).").foregroundStyle(Theme.secondary.color).monospacedDigit()
                Text(item).font(font).textSelection(.enabled)
            }
        }
    }
}

struct Heading: View {
    let text: String

    var body: some View {
        Text(text).font(.system(.headline, design: .serif))
    }
}

struct RouteTag: View {
    let route: String

    var body: some View {
        Text(route)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.accent.color)
            .background(Theme.accent.color.opacity(0.14), in: Capsule())
    }
}

struct NoteView: View {
    let note: Note

    var body: some View {
        Text(note.text).foregroundStyle(note.isError ? Theme.error.color : Theme.secondary.color).textSelection(.enabled)
    }
}

struct Progress: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(Theme.secondary.color)
        }
    }
}

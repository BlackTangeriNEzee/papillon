import SwiftUI
import Translation

final class FocusTextView: NSTextView {
    var onFocus: (Bool) -> Void = { _ in }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocus(false) }
        return accepted
    }
}

struct InputView: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onSubmit: () -> Void
    var onFocus: (Bool) -> Void = { _ in }
    var onEdit: () -> Void = {}
    var onOutside: () -> Void = {}
    var onCancel: () -> Bool = { false }
    static let font = NSFont.systemFont(ofSize: 15)
    static let inset = NSSize(width: 10, height: 10)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let size = scrollView.contentSize
        let textView = FocusTextView(frame: NSRect(origin: .zero, size: size))
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.onFocus = { focused in DispatchQueue.main.async { context.coordinator.parent.onFocus(focused) } }
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
        scrollView.documentView = textView
        context.coordinator.watch(textView)
        return scrollView
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.monitors.forEach { NSEvent.removeMonitor($0) }
        coordinator.monitors = []
        coordinator.observers.forEach { NotificationCenter.default.removeObserver($0) }
        coordinator.observers = []
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
                context.coordinator.parent.onFocus(textView.window?.firstResponder === textView)
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
        var monitors: [Any] = []
        var observers: [NSObjectProtocol] = []

        init(_ parent: InputView) { self.parent = parent }

        func watch(_ textView: NSTextView) {
            if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self, weak textView] event in
                guard let self, let textView, event.window === textView.window else { return event }
                if !textView.bounds.contains(textView.convert(event.locationInWindow, from: nil)) {
                    DispatchQueue.main.async { self.parent.onOutside() }
                }
                return event
            }) { monitors.append(monitor) }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self, weak textView] notification in
                guard let self, let textView, notification.object as? NSWindow === textView.window else { return }
                MainActor.assumeIsolated { self.parent.onOutside() }
            })
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEdit()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) { return parent.onCancel() }
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

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct MainView: View {
    @ObservedObject var store: Store
    @State private var compact = false

    private static let sections: [(page: Page, icon: String)] = [(.lookup, "character.book.closed"), (.screenshot, "camera.viewfinder"), (.documents, "doc.text"), (.settings, "gearshape")]

    static func title(_ page: Page) -> String {
        switch page {
        case .lookup: L("查词", "Lookup")
        case .screenshot: L("截图翻译", "Screenshot")
        case .documents: L("文档翻译", "Documents")
        case .settings: L("设置", "Settings")
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: compact ? 52 : 212)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(SidebarMaterial().ignoresSafeArea())
            Rectangle().fill(Theme.border.color).frame(width: 1).ignoresSafeArea()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.background.color.ignoresSafeArea())
        }
        .frame(minWidth: 520, minHeight: 348)
        .onGeometryChange(for: Bool.self, of: { $0.size.width < 640 }, action: { compact = $0 })
        .themed(background: false)
    }

    private func toggleRow(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(on ? Theme.accent.color : Theme.text.color)
                if !compact {
                    Text(title).lineLimit(1)
                    Spacer(minLength: 4)
                    Capsule()
                        .fill(on ? Theme.accent.color : Theme.border.color)
                        .frame(width: 26, height: 15)
                        .overlay(alignment: on ? .trailing : .leading) { Circle().fill(Color.white).padding(2) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: compact ? .center : .leading)
            .padding(.horizontal, compact ? 0 : 8)
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "1" : "0")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !compact {
                Text("Mini Dict").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary.color).padding(.horizontal, 8).padding(.bottom, 4)
            }
            ForEach(MainView.sections, id: \.page) { section in
                if section.page == .documents {
                    toggleRow(L("取词", "Word capture"), icon: "hand.point.up.left", on: store.wordCapture) { store.setWordCapture(!store.wordCapture) }
                    toggleRow(L("划词", "Select text"), icon: "text.cursor", on: store.selectTranslate) { store.setSelectTranslate(!store.selectTranslate) }
                }
                let selected = store.page == section.page
                Button { store.page = section.page } label: {
                    HStack(spacing: 8) {
                        Image(systemName: section.icon).frame(width: 18)
                        if !compact { Text(MainView.title(section.page)).lineLimit(1) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: compact ? .center : .leading)
                    .padding(.horizontal, compact ? 0 : 8)
                    .foregroundStyle(selected ? Theme.onAccent.color : Theme.text.color)
                    .background(selected ? Theme.accent.color : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(MainView.title(section.page))
                .accessibilityLabel(MainView.title(section.page))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if !compact {
                Text(L("收藏", "Favourites")).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary.color).padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
                if store.favourites.isEmpty {
                    Text(L("点结果旁的星标收藏", "Star a result to keep it here")).font(.caption).foregroundStyle(Theme.secondary.color).padding(.horizontal, 8)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.favourites.prefix(20), id: \.self) { item in
                            Button { store.search(item) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent.color).frame(width: 18)
                                    Text(item.replacingOccurrences(of: "\n", with: " ")).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 26)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(HistoryRowStyle())
                            .help(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.page == .lookup {
                SearchInput(store: store, search: store.main) { store.search(store.main.query) }
            } else {
                Text(MainView.title(store.page)).font(.system(.title2, design: .serif))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch store.page {
                    case .lookup: LookupContent(store: store, search: store.main)
                    case .screenshot: ScreenshotPage(store: store)
                    case .documents: DocumentsPage(documents: store.documents)
                    case .settings: SettingsView(store: store)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}

struct LookupContent: View {
    let store: Store
    @ObservedObject var search: Search

    var body: some View {
        if search.lookup == nil && search.note == nil { StartBlock(store: store) } else { LookupPage(store: store, search: search) }
    }
}

struct StartBlock: View {
    @ObservedObject var store: Store

    var body: some View {
        Text((0..<3).map { store.shortcuts[$0].display + " " + [L("显示/隐藏窗口", "show/hide window"), L("截图翻译", "screenshot translate"), L("翻译剪贴板", "translate clipboard")][$0] }.joined(separator: "   ·   "))
            .font(.caption)
            .foregroundStyle(Theme.secondary.color)
            .padding(.horizontal, 4)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            FeatureCard(icon: "camera.viewfinder", title: L("截图翻译", "Screenshot"), text: L("框选屏幕上的文字，译文直接贴在原处", "Select text on screen; the translation is pinned over it")) {
                Button(L("开始", "Start")) { store.takeScreenshot() }.buttonStyle(PillButtonStyle(small: true))
            }
            FeatureCard(icon: "text.cursor", title: L("划词", "Select to translate"), text: L("在任何应用里选中文字，译文出现在下方", "Select text in any app; the translation appears under it")) {
                Toggle("", isOn: Binding(get: { store.selectTranslate }, set: { store.setSelectTranslate($0) })).toggleStyle(ThemedToggleStyle()).labelsHidden()
            }
            FeatureCard(icon: "hand.point.up.left", title: L("取词", "Word capture"), text: L("按住 Option 把指针停在单词上即可查词", "Hold Option and rest the pointer on a word to look it up")) {
                Toggle("", isOn: Binding(get: { store.wordCapture }, set: { store.setWordCapture($0) })).toggleStyle(ThemedToggleStyle()).labelsHidden()
            }
            FeatureCard(icon: "doc.text", title: L("文档翻译", "Documents"), text: L("PDF、Word、PPT、Excel、EPUB、图片逐段对照翻译", "PDF, Word, PPT, Excel, EPUB and images, paragraph by paragraph")) {
                Button(L("打开", "Open")) { store.page = .documents }.buttonStyle(PillButtonStyle(small: true))
            }
        }
        if let note = store.selectNote { NoteView(note: note) }
        if let note = store.captureNote { NoteView(note: note) }
        SourcesCard(store: store)
    }
}

struct FeatureCard<Action: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent.color)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.color.opacity(0.14), in: Circle())
                Text(title).font(.system(.headline, design: .serif)).lineLimit(1)
            }
            Text(text).font(.callout).foregroundStyle(Theme.secondary.color).lineLimit(2, reservesSpace: true)
            HStack {
                Spacer()
                action()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .card(padding: 12)
    }
}

struct SourcesCard: View {
    @ObservedObject var store: Store
    @State private var apple: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(Theme.accent.color)
                Text(L("翻译来源", "Sources")).font(.system(.headline, design: .serif))
            }
            row(L("有道词典", "Youdao dictionary"), on: true, L("单词和短语总是先查有道", "Words and phrases always try Youdao first"), isDefault: false)
            let firstEnabled = store.sources.first { item in item.enabled && SourcesCard.ready(item.source, store.providers, apple) }?.id
            ForEach(store.sources) { item in
                let ready = SourcesCard.ready(item.source, store.providers, apple)
                row(item.source.name(store.providers), on: item.enabled && ready, item.enabled ? status(item.source) : L("已关闭", "Off"), isDefault: item.id == firstEnabled)
            }
        }
        .card(padding: 12)
        .task {
            guard #available(macOS 26.0, *) else {
                apple = L("需要 macOS 26", "Needs macOS 26")
                return
            }
            let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: Locale.Language(identifier: "zh-Hans"))
            apple = status == .installed ? nil : L("未下载语言包", "Language pack not downloaded")
        }
    }

    static func ready(_ source: Source, _ providers: [Provider], _ apple: String?) -> Bool {
        switch source {
        case .provider(let id): providers.first { $0.id == id }?.usable ?? false
        case .apple: apple == nil
        default: true
        }
    }

    private func status(_ source: Source) -> String {
        switch source {
        case .provider(let id):
            guard let provider = store.providers.first(where: { $0.id == id }), provider.usable else { return L("未填密钥", "No key") }
            return L("已配置 · ", "Configured · ") + provider.trimmed.model
        case .google: return L("免费 · 非官方接口", "Free · unofficial endpoint")
        case .apple: return apple ?? L("免费 · 本机", "Free · on this Mac")
        case .mymemory: return L("免费 · 每日限额", "Free · daily limit")
        }
    }

    private func row(_ name: String, on: Bool, _ status: String, isDefault: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(on ? Color.green : Theme.border.color).frame(width: 8, height: 8)
            Text(name).lineLimit(1)
            if isDefault { DefaultBadge() }
            Spacer(minLength: 8)
            Text(status).font(.callout).foregroundStyle(Theme.secondary.color).lineLimit(1)
        }
        .frame(height: 22)
    }
}

struct DefaultBadge: View {
    var body: some View {
        Text(L("默认", "Default"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.onAccent.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.accent.color, in: Capsule())
    }
}

struct SearchInput: View {
    @ObservedObject var store: Store
    @ObservedObject var search: Search
    let submit: () -> Void
    @State private var cardHeight: CGFloat = 0
    private static let rowHeight: CGFloat = 26

    private var matches: [String] {
        let typed = search.query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !typed.isEmpty else { return Array(store.history.prefix(10)) }
        let starting = store.history.filter { $0.lowercased().hasPrefix(typed) }
        let containing = store.history.filter { !$0.lowercased().hasPrefix(typed) && $0.lowercased().contains(typed) }
        return Array((starting + containing).prefix(10))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary.color).padding(.leading, 12).padding(.top, 12)
            InputView(text: $search.query, focusRequest: search.focusRequest, onSubmit: submit, onFocus: { focused in
            search.historyOpen = focused && search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }, onEdit: {
            search.historyOpen = true
        }, onOutside: {
            search.historyOpen = false
        }, onCancel: {
            guard search.historyOpen else { return false }
            search.historyOpen = false
            return true
        })
            .overlay(alignment: .topLeading) {
                if search.query.isEmpty {
                    Text(L("输入单词、短语或段落，回车翻译，Shift+回车换行", "Type a word, phrase or paragraph. Enter translates, Shift+Enter adds a line"))
                        .foregroundStyle(Theme.secondary.color)
                        .lineLimit(1)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
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
            .padding(8)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.surface.color, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.border.color))
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { cardHeight = $0 })
            .overlay(alignment: .topLeading) {
                if search.historyOpen && !matches.isEmpty { dropdown.offset(y: cardHeight + 6) }
            }
            .zIndex(1)
    }

    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(matches, id: \.self) { item in
                        Button { search.run(item) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock").font(.caption).foregroundStyle(Theme.secondary.color)
                                Text(item.replacingOccurrences(of: "\n", with: " ")).lineLimit(1).truncationMode(.tail).layoutPriority(1)
                                Spacer(minLength: 8)
                                Text(store.briefs[item] ?? "").font(.callout).foregroundStyle(Theme.secondary.color).lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: SearchInput.rowHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HistoryRowStyle())
                    }
                }
            }
            .frame(height: CGFloat(min(matches.count, 10)) * SearchInput.rowHeight)
            Divider().padding(.vertical, 2)
            Button(L("清空", "Clear")) {
                store.history = []
                search.historyOpen = false
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.accent.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.color, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border.color))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

struct HistoryRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HistoryRow(configuration: configuration)
    }

    private struct HistoryRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(hovering || configuration.isPressed ? Theme.accent.color.opacity(0.12) : Color.clear)
                .onHover { hovering = $0 }
        }
    }
}

struct QuickView: View {
    @ObservedObject var store: Store
    let search: Search
    let openMain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchInput(store: store, search: search) { search.run(search.query) }
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
    var compact = false

    var body: some View {
        if let note = search.note { NoteView(note: note) }
        if let lookup = search.lookup {
            VStack(alignment: .leading, spacing: 8) {
                if !(compact && lookup.kind == .paragraph) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if lookup.kind != .paragraph {
                        Text(lookup.text).font(.system(size: compact ? 20 : 26, weight: .semibold, design: .serif)).lineLimit(2).textSelection(.enabled)
                    }
                    if !compact, case .done(let entry?) = lookup.entry { Phonetics(search: search, word: lookup.text, entry: entry) }
                    Spacer(minLength: 4)
                    if case .done(.some) = lookup.entry { RouteTag(route: L("有道", "Youdao")) }
                    let on = store.favourites.contains(lookup.text)
                    Button { store.toggleFavourite(lookup.text) } label: {
                        Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? Theme.accent.color : Theme.secondary.color)
                    }
                    .buttonStyle(.plain)
                    .help(on ? L("取消收藏", "Remove favourite") : L("收藏", "Add favourite"))
                }
                }
                if compact, case .done(let entry?) = lookup.entry { Phonetics(search: search, word: lookup.text, entry: entry) }
                if let translation = lookup.translation { TranslationView(store: store, lookup: lookup, translation: translation) }
                if let entry = lookup.entry { EntryView(entry: entry) }
            }
            .card(padding: 12)
            if lookup.kind == .word && !compact { EnglishDefinitions(meanings: lookup.meanings) }
        }
    }
}

struct Phonetics: View {
    let search: Search
    let word: String
    let entry: DictEntry

    var body: some View {
        HStack(spacing: 10) {
            if let uk = entry.uk { phone(L("英", "UK"), uk, american: false) }
            if let us = entry.us { phone(L("美", "US"), us, american: true) }
            if let pinyin = entry.pinyin { Text("[\(pinyin)]").foregroundStyle(Theme.secondary.color).textSelection(.enabled) }
        }
        .font(.callout)
        .lineLimit(1)
    }

    private func phone(_ region: String, _ ipa: String, american: Bool) -> some View {
        HStack(spacing: 3) {
            Text(region).foregroundStyle(Theme.secondary.color)
            Text("[\(ipa)]").textSelection(.enabled)
            Button { search.play(Youdao.audio(word, american: american)) } label: {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent.color)
            }
            .buttonStyle(.plain)
            .help(L("发音", "Play"))
            .accessibilityLabel(region + " " + L("发音", "Play"))
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1] = (last.indices + [index], last.width + spacing + size.width, max(last.height, size.height))
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}

struct TranslationView: View {
    let store: Store
    let lookup: Lookup
    let translation: Load<Translation>

    var body: some View {
        switch translation {
        case .loading: Progress(text: L("翻译中…", "Translating…"))
        case .failed(let message): NoteView(note: Note(text: message, isError: true))
        case .done(let translation):
            VStack(alignment: .leading, spacing: 6) {
                RouteTag(route: translation.route)
                if let fallback = translation.fallback { Text(fallback).font(.caption).foregroundStyle(Theme.secondary.color).textSelection(.enabled) }
                if translation.candidates.isEmpty {
                    NoteView(note: Note(text: L("未找到翻译", "No translation found"), isError: true))
                } else if lookup.kind == .paragraph {
                    Text(translation.candidates[0]).font(.title3).lineSpacing(5).textSelection(.enabled)
                } else {
                    Numbered(items: translation.candidates)
                }
                if Translator.freeRoutes.contains(translation.route) && TextTools.isSentence(lookup.text) { FreeHint(store: store) }
                if !translation.senses.isEmpty {
                    Heading(text: L("释义", "Senses"))
                    Numbered(items: translation.senses)
                }
            }
        }
    }
}

struct EntryView: View {
    let entry: Load<DictEntry?>

    var body: some View {
        switch entry {
        case .loading: Progress(text: L("词典加载中…", "Loading dictionary…"))
        case .failed(let message): NoteView(note: Note(text: L("词典数据暂不可用", "Dictionary data unavailable") + " (\(message))", isError: true))
        case .done(nil): EmptyView()
        case .done(let entry?):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(entry.senses, id: \.self) { sense in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !sense.label.isEmpty {
                            Text(sense.label).font(.callout.weight(.semibold)).foregroundStyle(Theme.accent.color).frame(minWidth: 30, alignment: .leading)
                        }
                        Text(sense.text).lineSpacing(2).textSelection(.enabled)
                    }
                }
                if !entry.web.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(L("网络", "Web")).font(.caption).foregroundStyle(Theme.secondary.color).frame(minWidth: 30, alignment: .leading)
                        FlowLayout {
                            ForEach(entry.web, id: \.self) { value in
                                Text(value)
                                    .font(.caption)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Theme.accent.color.opacity(0.1), in: Capsule())
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

struct EnglishDefinitions: View {
    let meanings: Load<[Meaning]?>
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                switch meanings {
                case .loading: Progress(text: L("词典加载中…", "Loading dictionary…"))
                case .failed(let message): NoteView(note: Note(text: L("英英释义暂不可用", "English definitions unavailable") + " (\(message))", isError: true))
                case .done(nil): NoteView(note: Note(text: L("没有英英释义", "No English definitions found")))
                case .done(let meanings?):
                    ForEach(meanings, id: \.self) { meaning in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(EnglishDefinitions.abbreviation(meaning.partOfSpeech))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Theme.accent.color)
                                .frame(minWidth: 40, alignment: .leading)
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(meaning.definitions.enumerated()), id: \.offset) { index, definition in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(index + 1). ").foregroundStyle(Theme.secondary.color).monospacedDigit() + Text(definition.text)
                                        if !definition.example.isEmpty {
                                            Text(L("例：", "e.g. ") + definition.example).font(.callout).foregroundStyle(Theme.secondary.color).italic().padding(.leading, 16)
                                        }
                                    }
                                    .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text(L("英英释义", "English definitions")).font(.system(.headline, design: .serif))
        }
        .card()
    }

    static func abbreviation(_ partOfSpeech: String) -> String {
        ["noun": "n.", "verb": "v.", "adjective": "adj.", "adverb": "adv.", "interjection": "interj.", "preposition": "prep.", "conjunction": "conj.", "pronoun": "pron."][partOfSpeech.lowercased()] ?? partOfSpeech
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
                if Translator.freeRoutes.contains(result.route) { FreeHint(store: store) }
            }
            .card()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var tab = 0
    @FocusState private var focusedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        }
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
            Toggle(L("划词翻译", "Select to translate"), isOn: Binding(get: { store.selectTranslate }, set: { store.setSelectTranslate($0) }))
            if store.selectTranslate {
                Pills(selection: $store.selectAuto, options: [(false, L("先显示图标", "Show an icon first")), (true, L("自动显示", "Show automatically"))])
                    .padding(.leading, 16)
                Toggle(L("剪贴板回退（读不到选中文字时模拟 Cmd+C）", "Clipboard fallback (simulate Cmd+C when the selection cannot be read)"), isOn: $store.clipboardFallback)
                    .padding(.leading, 16)
            }
            if let note = store.selectNote { NoteView(note: note) }
        }
        .toggleStyle(ThemedToggleStyle())
    }

    private var api: some View {
        Group {
            orderCard
            ForEach($store.providers) { $provider in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(provider.title).font(.system(.headline, design: .serif))
                        Spacer()
                        Button(L("测试", "Test")) { store.testProvider(provider.id) }.buttonStyle(PillButtonStyle(prominent: false, small: true))
                        Button(L("删除", "Delete")) { store.deleteProvider(provider.id) }.buttonStyle(PillButtonStyle(prominent: false, small: true))
                    }
                    field(L("名称", "Name"), TextField("", text: $provider.name, prompt: Text("DeepSeek")))
                    field(L("API 地址", "Base URL"), TextField("", text: $provider.base, prompt: Text("https://api.example.com/v1")))
                    field(L("密钥", "Key"), SecureField("", text: $provider.key).focused($focusedKey, equals: provider.id).onSubmit { store.testProvider(provider.id) })
                    if let note = store.apiNotes[provider.id] { NoteView(note: note).font(.callout) }
                    field(L("模型", "Model"), TextField("", text: $provider.model, prompt: Text("model-name")))
                    row(L("格式", "Format")) {
                        Pills(selection: $provider.format, options: Provider.Format.allCases.map { ($0, $0.title) })
                    }
                }
                .padding(12)
                .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 8) {
                Button(L("添加 API", "Add API")) { store.addProvider(nil) }.buttonStyle(PillButtonStyle(small: true))
                ForEach(Provider.presets, id: \.name) { preset in
                    Button("+ " + preset.name) { store.addProvider(preset) }.buttonStyle(PillButtonStyle(prominent: false, small: true))
                }
            }
            Text(L("修改会自动保存；在密钥框按回车或离开时会测试该 API。", "Changes are saved automatically; pressing Enter in a key field, or leaving it, tests that API."))
                .font(.caption)
                .foregroundStyle(Theme.secondary.color)
        }
        .onChange(of: focusedKey) { old, _ in
            if let old, store.providers.first(where: { $0.id == old })?.trimmed.key.isEmpty == false { store.testProvider(old) }
        }
    }

    private var orderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("翻译顺序", "Translation order")).font(.system(.headline, design: .serif))
            Text(L("单词和短语总是先查有道词典；查不到的内容和句子、段落按下面的顺序尝试，第一个打开的是默认来源。拖动或用箭头调整顺序。", "Words and phrases always try the Youdao dictionary first. Anything else is tried in this order; the first enabled source is the default. Drag or use the arrows to reorder."))
                .font(.caption)
                .foregroundStyle(Theme.secondary.color)
                .fixedSize(horizontal: false, vertical: true)
            let firstEnabled = store.sources.first(where: \.enabled)?.id
            List {
                ForEach($store.sources) { $item in
                    let index = store.sources.firstIndex { $0.id == item.id } ?? 0
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal").foregroundStyle(Theme.secondary.color)
                        Text(item.source.name(store.providers)).foregroundStyle(item.enabled ? Theme.text.color : Theme.secondary.color)
                        if item.id == firstEnabled { DefaultBadge() }
                        Spacer()
                        Button { store.moveSource(IndexSet(integer: index), index - 1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.plain)
                            .disabled(index == 0)
                            .help(L("上移", "Move up"))
                            .accessibilityLabel(L("上移", "Move up") + " " + item.source.name(store.providers))
                        Button { store.moveSource(IndexSet(integer: index), index + 2) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.plain)
                            .disabled(index == store.sources.count - 1)
                            .help(L("下移", "Move down"))
                            .accessibilityLabel(L("下移", "Move down") + " " + item.source.name(store.providers))
                        Toggle("", isOn: $item.enabled).toggleStyle(ThemedToggleStyle()).labelsHidden().frame(width: 40)
                            .accessibilityLabel(item.source.name(store.providers))
                    }
                    .frame(height: 26)
                    .listRowBackground(Color.clear)
                }
                .onMove { store.moveSource($0, $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(store.sources.count) * 34)
            Button(L("恢复默认顺序", "Reset order")) { store.resetOrder() }.buttonStyle(PillButtonStyle(prominent: false, small: true))
        }
        .padding(12)
        .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 10))
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

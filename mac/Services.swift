import AppKit
import Translation
import Vision

enum UILanguage: String, CaseIterable {
    case system, zh, en
}

func L(_ zh: String, _ en: String) -> String {
    switch UILanguage(rawValue: UserDefaults.standard.string(forKey: "uiLanguage") ?? "") ?? .system {
    case .zh: return zh
    case .en: return en
    case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? zh : en
    }
}

enum Kind {
    case word, phrase, paragraph
}

struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct Translation {
    var route: String
    let candidates: [String]
    let senses: [String]
    var fallback: String?
}

struct Translated {
    var route: String
    let text: String
    var fallback: String?
}

struct Definition: Hashable {
    let text: String
    let example: String
}

struct Meaning: Hashable {
    let partOfSpeech: String
    let definitions: [Definition]
}

struct Sense: Hashable {
    let label: String
    let text: String
}

struct DictEntry {
    let uk: String?
    let us: String?
    let pinyin: String?
    let senses: [Sense]
    let web: [String]
}

struct Provider: Codable, Hashable, Identifiable {
    enum Format: String, Codable, CaseIterable {
        case openai, anthropic, gemini

        var title: String {
            switch self {
            case .openai: L("OpenAI 兼容", "OpenAI compatible")
            case .anthropic: "Anthropic"
            case .gemini: "Gemini"
            }
        }
    }

    var id = UUID().uuidString
    var name = ""
    var base = ""
    var key = ""
    var model = ""
    var format = Format.openai

    static let presets = [
        Provider(name: "DeepSeek", base: "https://api.deepseek.com/v1", model: "deepseek-chat"),
        Provider(name: "OpenAI", base: "https://api.openai.com/v1", model: "gpt-4o-mini"),
    ]

    var trimmed: Provider {
        Provider(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), base: base.trimmingCharacters(in: .whitespacesAndNewlines), key: key.trimmingCharacters(in: .whitespacesAndNewlines), model: model.trimmingCharacters(in: .whitespacesAndNewlines), format: format)
    }

    var title: String { name.isEmpty ? L("未命名", "Unnamed") : name }
    var usable: Bool { let clean = trimmed; return !clean.key.isEmpty && !clean.base.isEmpty && !clean.model.isEmpty }
    var route: String { "\(title) · \(model)" }

    static func stored() -> [Provider] {
        load().providers
    }

    static func decode(_ value: Any) throws -> [Provider] {
        let data: Data
        switch value {
        case let bytes as Data: data = bytes
        case let text as String: data = Data(text.utf8)
        default: throw Failure(L("类型不对：", "unexpected type: ") + String(describing: type(of: value)))
        }
        do {
            return try JSONDecoder().decode([Provider].self, from: data)
        } catch {
            throw Failure(error.localizedDescription)
        }
    }

    static func load() -> (providers: [Provider], error: String?) {
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: "providers") {
            do {
                return (try decode(value), nil)
            } catch {
                return ([], L("API 设置无法读取，已保留原值：", "Provider settings could not be read, the stored value was left untouched: ") + error.localizedDescription)
            }
        }
        let migrated = [("deepseek", presets[0]), ("openai", presets[1])].map { prefix, preset in
            var provider = preset
            provider.id = UUID().uuidString
            let legacy = prefix == "openai" ? "api" : nil
            func value(_ suffix: String) -> String? { defaults.string(forKey: prefix + suffix).flatMap { $0.isEmpty ? nil : $0 } ?? legacy.flatMap { defaults.string(forKey: $0 + suffix) }.flatMap { $0.isEmpty ? nil : $0 } }
            provider.key = value("Key") ?? ""
            provider.base = value("Base") ?? preset.base
            provider.model = value("Model") ?? preset.model
            return (prefix, provider)
        }
        save(migrated.map(\.1))
        let order = (defaults.stringArray(forKey: "sourceOrder") ?? []).map { id in migrated.first { $0.0 == id }.map { Source.provider($0.1.id).id } ?? id }
        if defaults.stringArray(forKey: "sourceOrder") != nil { defaults.set(order, forKey: "sourceOrder") }
        if let enabled = defaults.stringArray(forKey: "sourceEnabled") {
            defaults.set(enabled.map { id in migrated.first { $0.0 == id }.map { Source.provider($0.1.id).id } ?? id }, forKey: "sourceEnabled")
        }
        for prefix in ["deepseek", "openai", "api"] {
            for suffix in ["Key", "Base", "Model"] { defaults.removeObject(forKey: prefix + suffix) }
        }
        return (migrated.map(\.1), nil)
    }

    static var backupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ZhaocaiDict/providers-backup.json")
    }

    @discardableResult
    static func save(_ providers: [Provider]) -> String? {
        guard let data = try? JSONEncoder().encode(providers) else { return L("API 设置无法保存", "Provider settings could not be saved") }
        UserDefaults.standard.set(data, forKey: "providers")
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: backupURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            return nil
        } catch {
            return L("API 设置已保存，但备份失败：", "Provider settings were saved, but the backup failed: ") + error.localizedDescription
        }
    }

    static func restoreBackup() throws -> [Provider] {
        let data: Data
        do {
            data = try Data(contentsOf: backupURL)
        } catch {
            throw Failure(L("找不到备份：", "No backup found: ") + backupURL.path)
        }
        return try decode(data)
    }

    static func active() -> [Provider] {
        let providers = stored()
        return Source.chain().compactMap { source in
            guard case .provider(let id) = source else { return nil }
            return providers.first { $0.id == id && $0.usable }?.trimmed
        }
    }
}

enum Source: Hashable, Identifiable {
    case provider(String)
    case google, apple, mymemory

    static let free: [Source] = [.google, .apple, .mymemory]

    var id: String {
        switch self {
        case .provider(let id): "provider:" + id
        case .google: "google"
        case .apple: "apple"
        case .mymemory: "mymemory"
        }
    }

    init?(id: String) {
        if id.hasPrefix("provider:") {
            self = .provider(String(id.dropFirst("provider:".count)))
        } else if let free = Source.free.first(where: { $0.id == id }) {
            self = free
        } else {
            return nil
        }
    }

    func name(_ providers: [Provider]) -> String {
        switch self {
        case .provider(let id): providers.first { $0.id == id }?.title ?? id
        case .google: Translator.google
        case .apple: Translator.apple
        case .mymemory: Translator.myMemoryRoute
        }
    }

    static func defaultOrder(_ providers: [Provider]) -> [Source] {
        providers.map { .provider($0.id) } + free
    }

    static func stored(_ providers: [Provider] = Provider.stored()) -> [(source: Source, enabled: Bool)] {
        let defaults = UserDefaults.standard
        let valid = defaultOrder(providers)
        let saved = (defaults.stringArray(forKey: "sourceOrder") ?? []).compactMap(Source.init(id:)).filter(valid.contains)
        var order: [Source] = []
        for source in saved + valid where !order.contains(source) { order.append(source) }
        let savedIDs = Set(defaults.stringArray(forKey: "sourceOrder") ?? [])
        let enabled = defaults.stringArray(forKey: "sourceEnabled").map(Set.init)
        return order.map { source in
            guard let enabled else { return (source, true) }
            return (source, enabled.contains(source.id) || !savedIDs.contains(source.id))
        }
    }

    static func save(_ sources: [(source: Source, enabled: Bool)]) {
        UserDefaults.standard.set(sources.map(\.source.id), forKey: "sourceOrder")
        UserDefaults.standard.set(sources.filter(\.enabled).map(\.source.id), forKey: "sourceEnabled")
    }

    static func chain() -> [Source] {
        stored().filter(\.enabled).map(\.source)
    }
}

enum Net {
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"))!
    }

    static func fetch(_ request: URLRequest, session: URLSession = .shared) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure(L("网络错误", "Network error") + " (\(request.url?.host ?? "")): \(error.localizedDescription)")
        }
    }

    static func json(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data)
    }
}

enum TextTools {
    static let punctuation = try! Regex("[\\s.,!?;:。，！？；：]+")
    static let fence = try! Regex("^```(?:json)?\\s*|\\s*```$")
    static let block = try! Regex("(?is)<(style|script)\\b.*?</\\1\\s*>")
    static let tag = try! Regex("<[^>]*>")
    static let entity = try! Regex("&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);")
    static let space = try! Regex("\\s+")

    static func isCJK(_ text: String) -> Bool { text.range(of: "[\\u3400-\\u9fff\\uf900-\\ufaff]", options: .regularExpression) != nil }
    static func isWord(_ text: String) -> Bool { text.range(of: "^[a-z][a-z'-]*$", options: [.regularExpression, .caseInsensitive]) != nil }

    static func isSentence(_ text: String) -> Bool {
        isCJK(text) ? text.count >= 8 : text.split(whereSeparator: \.isWhitespace).count >= 3
    }

    static func kind(_ text: String) -> Kind {
        if isWord(text) { return .word }
        let short = text.count < 60 && text.split(whereSeparator: \.isWhitespace).count <= 6
        let oneSentence = text.range(of: "[.!?。！？]\\s*\\S", options: .regularExpression) == nil
        return short && oneSentence && !text.contains(where: \.isNewline) ? .phrase : .paragraph
    }
    static func norm(_ text: String) -> String { text.lowercased().replacing(punctuation, with: "") }

    static func plain(_ html: String) -> String {
        html.replacing(block, with: "")
            .replacing(tag, with: "")
            .replacing(entity) { match in
                let name = String(match.output[1].substring ?? "")
                switch name {
                case "amp": return "&"
                case "lt": return "<"
                case "gt": return ">"
                case "quot": return "\""
                case "apos": return "'"
                case "nbsp": return " "
                default:
                    let number = name.hasPrefix("#x") || name.hasPrefix("#X") ? UInt32(name.dropFirst(2), radix: 16) : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
                    return number.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? "&\(name);"
                }
            }
            .replacing(space, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chunks(_ text: String, size: Int = 450) -> [String] {
        var parts: [String] = []
        var rest = Substring(text)
        while rest.count > size {
            let head = rest.prefix(size)
            let cut = head.lastIndex(where: \.isWhitespace).flatMap { $0 > head.startIndex ? $0 : nil } ?? head.endIndex
            parts.append(String(rest[..<cut]))
            rest = rest[cut...]
        }
        parts.append(String(rest))
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

enum Translator {
    static let google = "Google"
    static var apple: String { L("Apple 翻译", "Apple Translation") }
    static let myMemoryRoute = "MyMemory"
    static var freeRoutes: [String] { [google, apple, myMemoryRoute] }

    static func withTimeout<T: Sendable>(_ seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw Failure(L("超时", "timed out") + " (\(Int(seconds)) s)")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    static func googleText(_ text: String, toEnglish: Bool) async throws -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var parts: [String] = []
            for part in TextTools.chunks(line, size: 1500) {
                let pair = toEnglish ? "sl=zh-CN&tl=en" : "sl=en&tl=zh-CN"
                var request = URLRequest(url: URL(string: (UserDefaults.standard.string(forKey: "googleBase") ?? "https://translate.googleapis.com") + "/translate_a/t?client=dict-chrome-ex&\(pair)&q=\(Net.encode(part))")!)
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, status) = try await Net.fetch(request)
                guard (200..<300).contains(status) else { throw Failure("HTTP \(status)") }
                guard let reply = Net.json(data) as? [Any] else { throw Failure(L("返回格式不对", "unexpected reply")) }
                parts.append(reply.map { ($0 as? String) ?? (($0 as? [Any])?.first as? String) ?? "" }.joined())
            }
            lines.append(parts.joined(separator: toEnglish ? " " : ""))
        }
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw Failure(L("没有返回译文", "no translation returned")) }
        return result
    }

    static func appleText(_ text: String, toEnglish: Bool) async throws -> String {
        guard #available(macOS 26.0, *) else { throw Failure(L("需要 macOS 26 或更新版本", "needs macOS 26 or later")) }
        let chinese = Locale.Language(identifier: "zh-Hans"), english = Locale.Language(identifier: "en")
        let session = TranslationSession(installedSource: toEnglish ? chinese : english, target: toEnglish ? english : chinese)
        do {
            return try await session.translate(text).targetText
        } catch TranslationError.notInstalled {
            throw Failure(L("语言包未下载（系统设置 > 通用 > 语言与地区 > 翻译语言）", "language pack not downloaded (System Settings > General > Language & Region > Translation Languages)"))
        }
    }

    static func chain<T>(api: (Provider) async throws -> T, free: (Source) async throws -> T) async throws -> (value: T, route: String, note: String?) {
        let sources = Source.chain()
        let providers = Provider.stored()
        guard !sources.isEmpty else { throw Failure(L("没有启用的翻译来源，请在“设置 > API > 翻译顺序”中打开至少一个", "No translation source is enabled; turn one on in Settings > API > Translation order")) }
        var notes: [String] = []
        for source in sources {
            do {
                if case .provider(let id) = source {
                    guard let provider = providers.first(where: { $0.id == id }), provider.usable else {
                        notes.append(source.name(providers) + L("：未填密钥，已跳过", ": no key, skipped"))
                        continue
                    }
                    return (try await api(provider.trimmed), provider.route, notes.isEmpty ? nil : notes.joined(separator: "; "))
                }
                return (try await free(source), source.name(providers), notes.isEmpty ? nil : notes.joined(separator: "; "))
            } catch {
                notes.append("\(source.name(providers)): \(error.localizedDescription)")
            }
        }
        throw Failure(notes.joined(separator: "; "))
    }

    static func freeSource(_ source: Source, _ text: String) async throws -> String {
        let toEnglish = TextTools.isCJK(text)
        return try await withTimeout(8) {
            switch source {
            case .google: try await googleText(text, toEnglish: toEnglish)
            case .apple: try await appleText(text, toEnglish: toEnglish)
            default: try await freeText(text, toEnglish: toEnglish)
            }
        }
    }

    static func translator(_ toEnglish: Bool) -> String {
        "You are a professional translator. Translate the user's text into natural, idiomatic \(toEnglish ? "English" : "Simplified Chinese") that a native speaker would write, keeping the meaning, tone and register. Never translate word for word and never add explanations."
    }

    static func withAPIs<T>(_ work: (Provider) async throws -> T) async throws -> (value: T, api: Provider, fallback: String?)? {
        let apis = Provider.active()
        guard !apis.isEmpty else { return nil }
        var errors: [String] = []
        for api in apis {
            do {
                let value = try await work(api)
                return (value, api, errors.isEmpty ? nil : errors.joined(separator: "; "))
            } catch {
                errors.append("\(api.title): \(error.localizedDescription)")
            }
        }
        throw Failure(errors.joined(separator: "; "))
    }

    static func search(_ text: String, isWord: Bool) async throws -> Translation {
        let toEnglish = TextTools.isCJK(text)
        let answered = try await chain(api: { api in
            let sensesRule = isWord ? ", \"senses\": [up to 5 main senses of this English word, each a short, natural one-line explanation in Simplified Chinese]" : ""
            let content = try await callApi(api, system: "\(translator(toEnglish)) Reply with JSON only, no code fences, in this shape: {\"translations\": [up to 5 distinct candidate translations, ordered from the most common everyday rendering to rarer ones]\(sensesRule)}", text: text)
            guard let reply = Net.json(Data(content.replacing(TextTools.fence, with: "").utf8)) as? [String: Any], let translations = reply["translations"] as? [Any] else {
                throw Failure(L("API 返回格式不对：", "Unexpected API reply: ") + content.prefix(300))
            }
            let senses = reply["senses"] as? [Any] ?? []
            return Translation(route: "", candidates: translations.prefix(5).map { "\($0)" }, senses: senses.prefix(5).map { "\($0)" })
        }, free: { source in
            guard source == .mymemory else { return Translation(route: "", candidates: [try await freeSource(source, text)], senses: []) }
            return try await withTimeout(8) { try await myMemoryCandidates(text, toEnglish: toEnglish) }
        })
        var translation = answered.value
        translation.route = answered.route
        translation.fallback = answered.note
        return translation
    }

    static func myMemoryCandidates(_ text: String, toEnglish: Bool) async throws -> Translation {
        let reply = try await myMemory(text, toEnglish: toEnglish)
        let matches = (reply["matches"] as? [[String: Any]] ?? []).filter { TextTools.norm($0["segment"] as? String ?? "") == TextTools.norm(text) }
        var seen: Set<String> = [TextTools.norm(text)]
        var candidates: [String] = []
        for candidate in [translatedText(reply)] + matches.map({ $0["translation"] as? String ?? "" }) {
            let key = TextTools.norm(candidate)
            guard !key.isEmpty, !seen.contains(key), !candidate.contains("\u{FFFD}") else { continue }
            seen.insert(key)
            candidates.append(candidate.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Translation(route: "", candidates: Array(candidates.prefix(5)), senses: [])
    }

    static func text(_ text: String) async throws -> Translated {
        let toEnglish = TextTools.isCJK(text)
        let answered = try await chain(api: { api in
            try await callApi(api, system: "\(translator(toEnglish)) Keep the paragraph breaks. Reply with the translation only.", text: text)
        }, free: { source in
            try await freeSource(source, text)
        })
        return Translated(route: answered.route, text: answered.value, fallback: answered.note)
    }

    static func freeText(_ text: String, toEnglish: Bool) async throws -> String {
        var lines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var parts: [String] = []
            for part in TextTools.chunks(line) {
                parts.append(translatedText(try await myMemory(part, toEnglish: toEnglish)))
            }
            lines.append(parts.joined(separator: toEnglish ? " " : ""))
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func translatedText(_ reply: [String: Any]) -> String {
        (reply["responseData"] as? [String: Any])?["translatedText"] as? String ?? ""
    }

    static func myMemory(_ text: String, toEnglish: Bool) async throws -> [String: Any] {
        let pair = toEnglish ? "zh-CN|en" : "en|zh-CN"
        let url = URL(string: "https://api.mymemory.translated.net/get?q=\(Net.encode(text))&langpair=\(Net.encode(pair))")!
        let (data, status) = try await Net.fetch(URLRequest(url: url))
        let failed = L("翻译失败：", "Translation failed: ")
        guard (200..<300).contains(status) else { throw Failure(failed + "HTTP \(status)") }
        guard let reply = Net.json(data) as? [String: Any] else { throw Failure(failed + String(decoding: data.prefix(300), as: UTF8.self)) }
        let code = "\(reply["responseStatus"] ?? "none")"
        guard code == "200" else { throw Failure(failed + "\(code) \(reply["responseDetails"] ?? "")") }
        return reply
    }

    static func callApi(_ api: Provider, system: String, text: String) async throws -> String {
        var base = api.base
        while base.hasSuffix("/") { base.removeLast() }
        let path: String
        switch api.format {
        case .openai: path = "/chat/completions"
        case .anthropic: path = "/messages"
        case .gemini: path = "/models/\(api.model):generateContent?key=\(Net.encode(api.key))"
        }
        guard let url = URL(string: base + path), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw Failure(L("API 地址无效：", "Invalid API base URL: ") + api.base)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any]
        switch api.format {
        case .openai:
            request.setValue("Bearer \(api.key)", forHTTPHeaderField: "Authorization")
            body = ["model": api.model, "temperature": 0.3, "messages": [["role": "system", "content": system], ["role": "user", "content": text]]]
        case .anthropic:
            request.setValue(api.key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": api.model, "max_tokens": 2048, "system": system, "messages": [["role": "user", "content": text]]]
        case .gemini:
            body = ["systemInstruction": ["parts": [["text": system]]], "contents": [["parts": [["text": text]]]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, status) = try await Net.fetch(request)
        let raw = String(decoding: data, as: UTF8.self)
        let reply = Net.json(data) as? [String: Any]
        guard (200..<300).contains(status) else {
            let error = reply?["error"]
            let message = (error as? [String: Any])?["message"] as? String ?? (error as? String) ?? String(raw.prefix(300))
            throw Failure("HTTP \(status) \(message)")
        }
        let content: String?
        switch api.format {
        case .openai: content = ((reply?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        case .anthropic: content = (reply?["content"] as? [[String: Any]])?.first?["text"] as? String
        case .gemini:
            let candidate = (reply?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any]
            content = (candidate?["parts"] as? [[String: Any]])?.first?["text"] as? String
        }
        guard let content else { throw Failure(L("API 返回格式不对：", "Unexpected API response: ") + raw.prefix(300)) }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WordSources {
    static func withLowercase<T>(_ word: String, _ lookup: (String) async throws -> T?) async throws -> T? {
        if let result = try await lookup(word) { return result }
        return word == word.lowercased() ? nil : try await lookup(word.lowercased())
    }

    static func meanings(_ word: String) async throws -> [Meaning]? {
        let url = URL(string: "https://en.wiktionary.org/api/rest_v1/page/definition/\(Net.encode(word))")!
        let (data, status) = try await Net.fetch(URLRequest(url: url))
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw Failure("HTTP \(status)") }
        guard let reply = Net.json(data) as? [String: Any] else { throw Failure(L("返回格式不对", "unexpected reply")) }
        var order: [String] = []
        var groups: [String: [[Definition]]] = [:]
        for entry in reply["en"] as? [[String: Any]] ?? [] {
            let partOfSpeech = entry["partOfSpeech"] as? String ?? ""
            let definitions = (entry["definitions"] as? [[String: Any]] ?? []).compactMap { item -> Definition? in
                let text = TextTools.plain(item["definition"] as? String ?? "")
                return text.isEmpty ? nil : Definition(text: text, example: TextTools.plain((item["examples"] as? [String])?.first ?? ""))
            }
            guard !definitions.isEmpty else { continue }
            if groups[partOfSpeech] == nil { order.append(partOfSpeech) }
            groups[partOfSpeech, default: []].append(definitions)
        }
        guard !order.isEmpty else { return nil }
        return order.map { partOfSpeech in
            let lists = groups[partOfSpeech]!
            var definitions: [Definition] = []
            var index = 0
            while definitions.count < 5 && lists.contains(where: { index < $0.count }) {
                for list in lists where index < list.count && definitions.count < 5 { definitions.append(list[index]) }
                index += 1
            }
            return Meaning(partOfSpeech: partOfSpeech, definitions: definitions)
        }
    }
}

enum Youdao {
    static func audio(_ word: String, american: Bool) -> URL {
        URL(string: "https://dict.youdao.com/dictvoice?audio=\(Net.encode(word))&type=\(american ? 2 : 1)")!
    }

    static func lookup(_ text: String) async throws -> DictEntry? {
        let chinese = TextTools.isCJK(text)
        let dict = chinese ? "ce" : "ec"
        var request = URLRequest(url: URL(string: "https://dict.youdao.com/jsonapi?q=\(Net.encode(text))&dicts=\(Net.encode("{\"count\":99,\"dicts\":[[\"\(dict)\",\"web_trans\"]]}"))")!)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, status) = try await Net.fetch(request)
        guard (200..<300).contains(status) else { throw Failure("HTTP \(status)") }
        guard let reply = Net.json(data) as? [String: Any] else { throw Failure(L("返回格式不对", "unexpected reply")) }
        guard let section = reply[dict] as? [String: Any] else { return nil }
        guard let word = (section["word"] as? [[String: Any]])?.first else { throw Failure(L("返回格式不对", "unexpected reply")) }
        let lines = (word["trs"] as? [[String: Any]] ?? []).compactMap { item -> Any? in
            (((item["tr"] as? [[String: Any]])?.first?["l"] as? [String: Any])?["i"])
        }
        let senses: [Sense] = lines.compactMap { line in
            if chinese {
                let parts = (line as? [Any] ?? []).map { ($0 as? String) ?? (($0 as? [String: Any])?["#text"] as? String) ?? "" }
                let text = parts.joined().trimmingCharacters(in: .whitespaces)
                return text.isEmpty ? nil : Sense(label: "", text: text)
            }
            guard let text = (line as? [Any])?.first as? String, !text.isEmpty else { return nil }
            let pieces = text.split(separator: " ", maxSplits: 1)
            return pieces.count == 2 && pieces[0].hasSuffix(".") ? Sense(label: String(pieces[0]), text: String(pieces[1])) : Sense(label: "", text: text)
        }
        guard !senses.isEmpty else { return nil }
        func phone(_ key: String) -> String? { (word[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let web = (((reply["web_trans"] as? [String: Any])?["web-translation"] as? [[String: Any]])?.first?["trans"] as? [[String: Any]] ?? []).compactMap { $0["value"] as? String }
        return DictEntry(uk: phone("ukphone"), us: phone("usphone"), pinyin: phone("phone"), senses: senses, web: Array(web.prefix(5)))
    }
}

struct TextLine {
    let text: String
    let box: CGRect
}

enum OCR {
    static func lines(_ image: CGImage) async throws -> [TextLine] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "zh-Hans"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { observation in
                observation.topCandidates(1).first.map { TextLine(text: $0.string, box: observation.boundingBox) }
            }
        }.value
    }

    static func words(_ image: CGImage) async throws -> [(text: String, box: CGRect)] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US", "zh-Hans"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image).perform([request])
            var words: [(text: String, box: CGRect)] = []
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let string = candidate.string
                string.enumerateSubstrings(in: string.startIndex..., options: .byWords) { word, range, _, _ in
                    guard let word, let box = try? candidate.boundingBox(for: range)?.boundingBox else { return }
                    words.append((word, box))
                }
            }
            return words
        }.value
    }

    static func join(_ texts: [String], separator: String = "\n") -> String {
        texts.joined(separator: separator).replacingOccurrences(of: "([\\u3400-\\u9fff])[ \\t]+(?=[\\u3400-\\u9fff])", with: "$1", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func recognize(_ image: CGImage) async throws -> String {
        join(try await lines(image).map(\.text))
    }
}

import AppKit
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
    let route: String
    let candidates: [String]
    let senses: [String]
}

struct Translated {
    let route: String
    let text: String
}

struct Definition: Hashable {
    let text: String
    let example: String
}

struct Meaning: Hashable {
    let partOfSpeech: String
    let definitions: [Definition]
}

struct Phonetic {
    let ipa: String?
    let audio: URL?
}

struct APISettings {
    var base = ""
    var key = ""
    var model = ""

    static func stored() -> APISettings {
        let defaults = UserDefaults.standard
        return APISettings(base: defaults.string(forKey: "apiBase") ?? "", key: defaults.string(forKey: "apiKey") ?? "", model: defaults.string(forKey: "apiModel") ?? "")
    }

    static func active() -> APISettings? {
        let settings = stored()
        return settings.base.isEmpty || settings.key.isEmpty || settings.model.isEmpty ? nil : settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(base, forKey: "apiBase")
        defaults.set(key, forKey: "apiKey")
        defaults.set(model, forKey: "apiModel")
    }
}

enum Net {
    static let phoneticSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForResource = 6
        return URLSession(configuration: configuration)
    }()

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
    static var free: String { L("免费", "Free") }

    static func translator(_ toEnglish: Bool) -> String {
        "You are a professional translator. Translate the user's text into natural, idiomatic \(toEnglish ? "English" : "Simplified Chinese") that a native speaker would write, keeping the meaning, tone and register. Never translate word for word and never add explanations."
    }

    static func search(_ text: String, isWord: Bool) async throws -> Translation {
        let toEnglish = TextTools.isCJK(text)
        if let api = APISettings.active() {
            let sensesRule = isWord ? ", \"senses\": [up to 5 main senses of this English word, each a short, natural one-line explanation in Simplified Chinese]" : ""
            let content = try await callApi(api, system: "\(translator(toEnglish)) Reply with JSON only, no code fences, in this shape: {\"translations\": [up to 5 distinct candidate translations, ordered from the most common everyday rendering to rarer ones]\(sensesRule)}", text: text)
            guard let reply = Net.json(Data(content.replacing(TextTools.fence, with: "").utf8)) as? [String: Any], let translations = reply["translations"] as? [Any] else {
                throw Failure(L("API 返回格式不对：", "Unexpected API reply: ") + content.prefix(300))
            }
            let senses = reply["senses"] as? [Any] ?? []
            return Translation(route: "API", candidates: translations.prefix(5).map { "\($0)" }, senses: senses.prefix(5).map { "\($0)" })
        }
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
        return Translation(route: free, candidates: Array(candidates.prefix(5)), senses: [])
    }

    static func text(_ text: String) async throws -> Translated {
        let toEnglish = TextTools.isCJK(text)
        if let api = APISettings.active() {
            return Translated(route: "API", text: try await callApi(api, system: "\(translator(toEnglish)) Keep the paragraph breaks. Reply with the translation only.", text: text))
        }
        return Translated(route: free, text: try await freeText(text, toEnglish: toEnglish))
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

    static func callApi(_ api: APISettings, system: String, text: String) async throws -> String {
        var base = api.base
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions"), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw Failure(L("API 地址无效：", "Invalid API base URL: ") + api.base)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(api.key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": api.model, "temperature": 0.3, "messages": [["role": "system", "content": system], ["role": "user", "content": text]]])
        let (data, status) = try await Net.fetch(request)
        let body = String(decoding: data, as: UTF8.self)
        let reply = Net.json(data) as? [String: Any]
        guard (200..<300).contains(status) else {
            let message = (reply?["error"] as? [String: Any])?["message"] as? String ?? String(body.prefix(300))
            throw Failure(L("API 错误：", "API error: ") + "HTTP \(status) \(message)")
        }
        guard let content = ((reply?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String else {
            throw Failure(L("API 返回格式不对：", "Unexpected API response: ") + body.prefix(300))
        }
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

    static func phonetic(_ word: String) async throws -> Phonetic? {
        let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(Net.encode(word))")!
        let (data, status) = try await Net.fetch(URLRequest(url: url), session: Net.phoneticSession)
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw Failure("HTTP \(status)") }
        guard let entries = Net.json(data) as? [[String: Any]] else { throw Failure(L("返回格式不对", "unexpected reply")) }
        let phonetics = entries.flatMap { $0["phonetics"] as? [[String: Any]] ?? [] }
        let ipa = entries.compactMap { $0["phonetic"] as? String }.first { !$0.isEmpty } ?? phonetics.compactMap { $0["text"] as? String }.first { !$0.isEmpty }
        let audio = phonetics.compactMap { $0["audio"] as? String }.first { !$0.isEmpty }.flatMap { URL(string: $0) }
        return Phonetic(ipa: ipa, audio: audio)
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

    static func join(_ texts: [String], separator: String = "\n") -> String {
        texts.joined(separator: separator).replacingOccurrences(of: "([\\u3400-\\u9fff])[ \\t]+(?=[\\u3400-\\u9fff])", with: "$1", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func recognize(_ image: CGImage) async throws -> String {
        join(try await lines(image).map(\.text))
    }
}

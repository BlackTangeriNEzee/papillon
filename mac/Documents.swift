import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct Paragraph: Identifiable {
    let id: Int
    let text: String
    var result: Load<Translated>?
}

enum DocumentReader {
    static let types = ["pdf", "docx", "pptx", "xlsx", "epub", "txt", "md", "png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp", "webp"]

    static func read(_ url: URL) async throws -> [String] {
        let parts: [String]
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw Failure(L("无法打开 PDF", "The PDF could not be opened")) }
            parts = (0..<document.pageCount).flatMap { pdfParagraphs(document.page(at: $0)?.string ?? "") }
        case "docx":
            parts = xmlParagraphs(try unzip(url, "word/document.xml"), paragraph: "w:p", run: "w:t")
        case "pptx":
            let slides = try list(url).filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }.sorted { number($0) < number($1) }
            parts = try slides.flatMap { xmlParagraphs(try unzip(url, $0), paragraph: "a:p", run: "a:t") }
        case "xlsx":
            parts = xmlParagraphs(try unzip(url, "xl/sharedStrings.xml"), paragraph: "si", run: "t")
        case "epub":
            parts = try epub(url)
        case "txt", "md":
            parts = blocks(try String(contentsOf: url, encoding: .utf8), joinLines: false)
        default:
            guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Failure(L("不支持的文件类型", "Unsupported file type")) }
            parts = Blocks.make(try await OCR.lines(image), image: image, size: CGSize(width: image.width, height: image.height)).map(\.text)
        }
        let chunks = parts.flatMap { TextTools.chunks($0, size: 1500) }
        guard !chunks.isEmpty else { throw Failure(L("文件里没有找到文字", "No text was found in the file")) }
        return chunks
    }

    static func blocks(_ text: String, joinLines: Bool) -> [String] {
        text.components(separatedBy: "\n\n").map { block in
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            return joinLines ? trimmed.split(whereSeparator: \.isNewline).joined(separator: TextTools.isCJK(trimmed) ? "" : " ") : trimmed
        }
        .filter { !$0.isEmpty }
    }

    static func pdfParagraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        func flush() {
            let joined = current.joined(separator: TextTools.isCJK(current.joined()) ? "" : " ")
            if !joined.isEmpty { paragraphs.append(joined) }
            current = []
        }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                continue
            }
            current.append(trimmed)
            if let last = trimmed.last, ".!?。！？:：".contains(last) { flush() }
        }
        flush()
        return paragraphs
    }

    static func number(_ path: String) -> Int {
        Int(path.filter(\.isNumber)) ?? 0
    }

    static func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(L("无法解压文件", "The file could not be unzipped") + " (unzip \(process.terminationStatus))") }
        return data
    }

    static func unzip(_ url: URL, _ member: String) throws -> String {
        String(decoding: try run(["-p", url.path, member]), as: UTF8.self)
    }

    static func list(_ url: URL) throws -> [String] {
        String(decoding: try run(["-Z1", url.path]), as: UTF8.self).split(separator: "\n").map(String.init)
    }

    static func xmlParagraphs(_ xml: String, paragraph: String, run: String) -> [String] {
        let paragraphs = try! Regex("(?s)<\(paragraph)(?:\\s[^>]*)?>(.*?)</\(paragraph)>")
        let runs = try! Regex("(?s)<\(run)(?:\\s[^>]*)?>(.*?)</\(run)>")
        return xml.matches(of: paragraphs).map { match in
            let inner = String(match.output[1].substring ?? "")
            return TextTools.plain(inner.matches(of: runs).map { String($0.output[1].substring ?? "") }.joined())
        }
        .filter { !$0.isEmpty }
    }

    static func epub(_ url: URL) throws -> [String] {
        let container = try unzip(url, "META-INF/container.xml")
        guard let rootMatch = container.firstMatch(of: try! Regex("full-path=\"([^\"]+)\"")) else { throw Failure(L("EPUB 格式不对", "Unexpected EPUB layout")) }
        let root = String(rootMatch.output[1].substring ?? "")
        let opf = try unzip(url, root)
        let folder = (root as NSString).deletingLastPathComponent
        var manifest: [String: String] = [:]
        for item in opf.matches(of: try! Regex("<item\\s[^>]*>")) {
            let tag = String(item.output[0].substring ?? "")
            if let id = tag.firstMatch(of: try! Regex("\\sid=\"([^\"]+)\""))?.output[1].substring, let href = tag.firstMatch(of: try! Regex("href=\"([^\"]+)\""))?.output[1].substring {
                manifest[String(id)] = String(href)
            }
        }
        let spine = opf.matches(of: try! Regex("<itemref\\s[^>]*idref=\"([^\"]+)\"")).compactMap { manifest[String($0.output[1].substring ?? "")] }
        let breaks = try! Regex("(?i)</p>|<br\\s*/?>|</h[1-6]>|</div>|</li>")
        return try spine.filter { $0.hasSuffix("html") || $0.hasSuffix("htm") }.flatMap { href -> [String] in
            let path = folder.isEmpty ? href : folder + "/" + href
            let html = try unzip(url, path.removingPercentEncoding ?? path).replacing(TextTools.block, with: "")
            return html.replacing(breaks, with: "\n\n").components(separatedBy: "\n\n").map(TextTools.plain).filter { !$0.isEmpty }
        }
    }
}

@MainActor
final class Documents: ObservableObject {
    @Published var name = ""
    @Published var paragraphs: [Paragraph] = []
    @Published var note: Note?
    @Published var question = ""
    @Published var answer: Load<String>?
    @Published var answerNote: Note?
    private var job: Task<Void, Never>?

    var done: Int { paragraphs.filter { if case .done = $0.result { true } else if case .failed = $0.result { true } else { false } }.count }

    var translations: [String] {
        paragraphs.map { if case .done(let translated) = $0.result { translated.text } else { "" } }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentReader.types.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        clear()
        name = url.lastPathComponent
        note = Note(text: L("读取中…", "Reading…"))
        job = Task {
            let read: Result<[String], Error> = await Task.detached {
                do { return .success(try await DocumentReader.read(url)) } catch { return .failure(error) }
            }.value
            switch read {
            case .failure(let error):
                note = Note(text: L("读取失败：", "Could not read the file: ") + error.localizedDescription, isError: true)
            case .success(let texts):
                note = nil
                paragraphs = texts.enumerated().map { Paragraph(id: $0.offset, text: $0.element) }
                await translate(texts)
            }
        }
    }

    private func translate(_ texts: [String]) async {
        await withTaskGroup(of: (Int, Load<Translated>).self) { group in
            var next = 0
            while next < min(3, texts.count) {
                let index = next
                paragraphs[index].result = .loading
                group.addTask { (index, await load { try await Translator.text(texts[index]) }) }
                next += 1
            }
            for await (index, result) in group {
                guard !Task.isCancelled else { break }
                paragraphs[index].result = result
                if next < texts.count {
                    let index = next
                    paragraphs[index].result = .loading
                    group.addTask { (index, await load { try await Translator.text(texts[index]) }) }
                    next += 1
                }
            }
            if Task.isCancelled {
                group.cancelAll()
                for index in paragraphs.indices where paragraphs[index].result == nil || isLoading(paragraphs[index].result) {
                    paragraphs[index].result = .failed(L("已取消", "Cancelled"))
                }
            }
        }
    }

    private func isLoading(_ result: Load<Translated>?) -> Bool {
        if case .loading = result { true } else { false }
    }

    func cancel() {
        job?.cancel()
    }

    func clear() {
        job?.cancel()
        job = nil
        name = ""
        paragraphs = []
        note = nil
        question = ""
        answer = nil
        answerNote = nil
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translations.filter { !$0.isEmpty }.joined(separator: "\n\n"), forType: .string)
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md")!, .plainText]
        panel.nameFieldStringValue = (name as NSString).deletingPathExtension + L("-译文", "-translation") + ".md"
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let translations = self.translations
        let body: String
        if url.pathExtension.lowercased() == "md" {
            let sections: [String] = paragraphs.map { paragraph in
                let quoted = "> " + paragraph.text.replacingOccurrences(of: "\n", with: "\n> ")
                return quoted + "\n\n" + translations[paragraph.id]
            }
            body = "# \(name)\n\n" + sections.joined(separator: "\n\n") + "\n"
        } else {
            body = translations.filter { !$0.isEmpty }.joined(separator: "\n\n") + "\n"
        }
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            note = Note(text: L("已导出：", "Exported: ") + url.path)
        } catch {
            note = Note(text: L("导出失败：", "Export failed: ") + error.localizedDescription, isError: true)
        }
    }

    func ask() {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let full = paragraphs.map(\.text).joined(separator: "\n\n")
        let limit = 60_000
        let context = String(full.prefix(limit))
        answerNote = full.count > limit ? Note(text: L("文档较长，只发送了前 \(limit) 个字符。", "The document is long; only the first \(limit) characters were sent.")) : nil
        answer = .loading
        Task {
            answer = await load {
                guard let answered = try await Translator.withAPIs({ api in
                    try await Translator.callApi(api, system: "Answer the user's question using only the document below. Reply in the language of the question. If the document does not contain the answer, say so.\n\nDocument:\n\(context)", text: question)
                }) else { throw Failure(L("问答需要 API 密钥", "Q&A needs an API key")) }
                return answered.api.route + "\n" + answered.value
            }
        }
    }
}

struct DocumentsPage: View {
    @ObservedObject var documents: Documents

    var body: some View {
        if documents.paragraphs.isEmpty {
            dropZone
            if let note = documents.note { NoteView(note: note) }
        } else {
            header
            ForEach(documents.paragraphs) { paragraph in
                VStack(alignment: .leading, spacing: 6) {
                    Text(paragraph.text).foregroundStyle(Theme.secondary.color).textSelection(.enabled)
                    switch paragraph.result {
                    case nil: EmptyView()
                    case .loading: Progress(text: L("翻译中…", "Translating…"))
                    case .failed(let message): NoteView(note: Note(text: message, isError: true))
                    case .done(let translated): Text(translated.text).lineSpacing(3).textSelection(.enabled)
                    }
                }
                .card(padding: 12)
            }
            questions
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Button { documents.choose() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.onAccent.color)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent.color, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L("选择文件", "Choose a file"))
            Text(L("拖入或选择文件，逐段对照翻译", "Drop or choose a file to translate it paragraph by paragraph")).font(.headline)
            HStack(spacing: 14) {
                ForEach([("doc.text", "Word"), ("doc.richtext", "PDF"), ("rectangle.on.rectangle", "PPT"), ("tablecells", "Excel"), ("book", "EPUB"), ("photo", L("图片", "Image")), ("text.alignleft", "TXT")], id: \.1) { item in
                    VStack(spacing: 4) {
                        Image(systemName: item.0).font(.title2).foregroundStyle(Theme.accent.color)
                        Text(item.1).font(.caption).foregroundStyle(Theme.secondary.color)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .background(Theme.surface.color, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent.color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(Theme.accent.color)
                Text(documents.name).font(.system(.headline, design: .serif)).lineLimit(1)
                Text(L("\(documents.paragraphs.count) 段", "\(documents.paragraphs.count) paragraphs")).font(.caption).foregroundStyle(Theme.secondary.color)
                Spacer()
            }
            ProgressView(value: Double(documents.done), total: Double(max(documents.paragraphs.count, 1)))
                .tint(Theme.accent.color)
            HStack(spacing: 8) {
                Text("\(documents.done) / \(documents.paragraphs.count)").font(.caption).foregroundStyle(Theme.secondary.color).monospacedDigit()
                Spacer()
                if documents.done < documents.paragraphs.count {
                    Button(L("取消", "Cancel")) { documents.cancel() }.buttonStyle(PillButtonStyle(prominent: false, small: true))
                }
                Button(L("导出译文", "Export translation")) { documents.export() }.buttonStyle(PillButtonStyle(small: true))
                Button(L("复制全部", "Copy all")) { documents.copyAll() }.buttonStyle(PillButtonStyle(prominent: false, small: true))
                Button(L("清除", "Clear")) { documents.clear() }.buttonStyle(PillButtonStyle(prominent: false, small: true))
            }
            if let note = documents.note { NoteView(note: note).font(.caption) }
        }
        .card(padding: 12)
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble").foregroundStyle(Theme.accent.color)
                Text(L("问答速读", "Q&A")).font(.system(.headline, design: .serif))
            }
            let hasAPI = !APISettings.active().isEmpty
            HStack(spacing: 8) {
                TextField(L("就这份文档提问", "Ask about this document"), text: $documents.question)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.background.color, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border.color))
                    .onSubmit { documents.ask() }
                Button(L("提问", "Ask")) { documents.ask() }.buttonStyle(PillButtonStyle(small: true))
            }
            .disabled(!hasAPI)
            if !hasAPI { NoteView(note: Note(text: L("问答需要在设置中填写 DeepSeek 或 OpenAI 密钥", "Q&A needs a DeepSeek or OpenAI key in Settings"))).font(.caption) }
            if let note = documents.answerNote { NoteView(note: note).font(.caption) }
            switch documents.answer {
            case nil: EmptyView()
            case .loading: Progress(text: L("思考中…", "Thinking…"))
            case .failed(let message): NoteView(note: Note(text: message, isError: true))
            case .done(let text):
                let parts = text.split(separator: "\n", maxSplits: 1).map(String.init)
                RouteTag(route: parts.first ?? "")
                Text(parts.count > 1 ? parts[1] : "").lineSpacing(3).textSelection(.enabled)
            }
        }
        .card(padding: 12)
    }
}

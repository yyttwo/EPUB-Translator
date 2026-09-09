import Compression
import Foundation

enum FileAccessError: LocalizedError, Equatable {
    case fileMissing
    case invalidEPUB
    case unsupportedEPUBCompression
    case permissionExpired
    case readFailed
    case sourceOverwrite
    case targetNotWritable
    case saveFailed
    case diskSpaceLow
    case unsupportedEncryptedContent
    case checkpointRecoveryFailed
    case uncoveredVisibleText
    case translationMismatch
    case rebuildFailed

    var errorDescription: String? {
        switch self {
        case .fileMissing: return "文件不存在或已被移动。"
        case .invalidEPUB: return "无法识别这本 EPUB 的目录或正文结构。"
        case .unsupportedEPUBCompression: return "这本 EPUB 使用了当前不支持的压缩格式。"
        case .permissionExpired: return "文件访问权限已失效，请重新选择文件。"
        case .readFailed: return "无法读取所选 EPUB。"
        case .sourceOverwrite: return "输出不能覆盖源 EPUB，请选择其他位置。"
        case .targetNotWritable: return "目标位置不可写，请重新选择保存位置。"
        case .saveFailed: return "保存输出失败。"
        case .diskSpaceLow: return "Mac 可用空间不足。"
        case .unsupportedEncryptedContent: return "正文使用了当前不支持的加密方式。"
        case .checkpointRecoveryFailed: return "无法恢复上次翻译任务。"
        case .uncoveredVisibleText:
            return "这本 EPUB 含有尚未纳入翻译范围的可见文字，已停止处理以避免生成漏译文件。"
        case .translationMismatch: return "译文与 EPUB 正文单元不匹配，已停止导出以避免生成损坏文件。"
        case .rebuildFailed: return "无法重建有效的中文版 EPUB。"
        }
    }
}

protocol SecurityScopedURLAccessing {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

struct SystemSecurityScopedURLAccess: SecurityScopedURLAccessing {
    func startAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

struct EPUBFileInfo: Equatable {
    let fileName: String
    let bookTitle: String?
    let byteCount: UInt64
    let readingDocumentCount: Int
    let translationUnitCount: Int
    let sourceCharacterCount: Int
    let headerDescription: String
}

struct EPUBTranslationUnit: Equatable, Identifiable {
    let id: String
    let documentPath: String
    let blockIndex: Int
    let pieceIndex: Int
    let pieceCount: Int
    let blockKind: EPUBTextBlockKind
    let sourceText: String
}

enum EPUBTextBlockKind: String, Equatable {
    case standard
    case preformatted

    var translationSeparator: String {
        switch self {
        case .standard: return " "
        case .preformatted: return "\n\n"
        }
    }
}

struct EPUBTextBlock: Equatable {
    let sourceText: String
    let kind: EPUBTextBlockKind
}

struct EPUBTranslationPlan: Equatable {
    let info: EPUBFileInfo
    let packagePath: String
    let documentPaths: [String]
    let units: [EPUBTranslationUnit]
}

enum TranslationTimeEstimator {
    static func estimatedSeconds(for info: EPUBFileInfo, provider: ProviderID) -> TimeInterval {
        guard info.translationUnitCount > 0 else { return 0 }
        let secondsPerUnit: Double
        let charactersPerSecond: Double
        switch provider {
        case .qwen:
            secondsPerUnit = 2.8
            charactersPerSecond = 240
        case .deepSeek:
            secondsPerUnit = 3.2
            charactersPerSecond = 220
        }
        let estimate = Double(info.translationUnitCount) * secondsPerUnit
            + Double(info.sourceCharacterCount) / charactersPerSecond
        return max(30, estimate)
    }

    static func displayText(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "等待选择书籍" }
        let roundedMinutes = max(1, Int(ceil(seconds / 60)))
        if roundedMinutes < 60 {
            return "约 \(roundedMinutes) 分钟"
        }
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        return minutes == 0 ? "约 \(hours) 小时" : "约 \(hours) 小时 \(minutes) 分钟"
    }
}

enum TranslationUnitPlanner {
    static let maximumCharactersPerUnit = 1_200

    static func units(from blocks: [String]) -> [String] {
        blocks.flatMap { splitBlock($0, maximumCharacters: maximumCharactersPerUnit) }
    }

    static func units(from block: EPUBTextBlock) -> [String] {
        switch block.kind {
        case .standard:
            return splitBlock(block.sourceText, maximumCharacters: maximumCharactersPerUnit)
        case .preformatted:
            return preformattedParagraphs(block.sourceText).flatMap {
                splitBlock($0, maximumCharacters: maximumCharactersPerUnit)
            }
        }
    }

    static func normalizedPreformattedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func preformattedParagraphs(_ rawText: String) -> [String] {
        let text = normalizedPreformattedText(rawText)
        guard !text.isEmpty else { return [] }
        var paragraphs: [String] = []
        var lines: [String] = []

        func flush() {
            let paragraph = normalizedText(lines.joined(separator: " "))
            if !paragraph.isEmpty { paragraphs.append(paragraph) }
            lines.removeAll(keepingCapacity: true)
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                flush()
            } else {
                lines.append(String(line))
            }
        }
        flush()
        return paragraphs
    }

    private static func splitBlock(_ rawText: String, maximumCharacters: Int) -> [String] {
        let text = normalizedText(rawText)
        guard !text.isEmpty else { return [] }
        guard text.count > maximumCharacters else { return [text] }

        var sentences: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.bySentences]
        ) { substring, _, _, _ in
            if let substring {
                let sentence = normalizedText(substring)
                if !sentence.isEmpty { sentences.append(sentence) }
            }
        }
        if sentences.isEmpty { sentences = [text] }

        var result: [String] = []
        var current = ""
        for sentence in sentences {
            for piece in hardSplit(sentence, maximumCharacters: maximumCharacters) {
                if current.isEmpty {
                    current = piece
                } else if current.count + 1 + piece.count <= maximumCharacters {
                    current += " " + piece
                } else {
                    result.append(current)
                    current = piece
                }
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func hardSplit(_ text: String, maximumCharacters: Int) -> [String] {
        guard text.count > maximumCharacters else { return [text] }
        var pieces: [String] = []
        var remaining = text[...]
        while remaining.count > maximumCharacters {
            let limit = remaining.index(remaining.startIndex, offsetBy: maximumCharacters)
            let candidate = remaining[..<limit]
            let cut = candidate.lastIndex(where: { $0.isWhitespace }) ?? limit
            let piece = normalizedText(String(remaining[..<cut]))
            if !piece.isEmpty { pieces.append(piece) }
            remaining = remaining[cut...].drop(while: { $0.isWhitespace })
        }
        let tail = normalizedText(String(remaining))
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    static func normalizedText(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

final class EPUBFileAccessService {
    private let fileManager: FileManager
    private let scopedAccess: any SecurityScopedURLAccessing

    init(
        fileManager: FileManager = .default,
        scopedAccess: any SecurityScopedURLAccessing = SystemSecurityScopedURLAccess()
    ) {
        self.fileManager = fileManager
        self.scopedAccess = scopedAccess
    }

    func inspectSelectedEPUB(at url: URL) throws -> EPUBFileInfo {
        try loadTranslationPlan(at: url).info
    }

    func translationUnits(at url: URL) throws -> [String] {
        try loadTranslationPlan(at: url).units.map(\.sourceText)
    }

    func loadTranslationPlan(at url: URL) throws -> EPUBTranslationPlan {
        guard url.pathExtension.lowercased() == "epub" else { throw FileAccessError.invalidEPUB }
        guard fileManager.fileExists(atPath: url.path) else { throw FileAccessError.fileMissing }

        return try withScopedAccess(to: url) {
            do {
                let archiveData = try Data(contentsOf: url, options: [.mappedIfSafe])
                let archive = try EPUBZIPArchive(data: archiveData)
                let package = try EPUBPackageInspector.inspect(archive: archive)
                var units: [EPUBTranslationUnit] = []
                for document in package.documents {
                    for (blockIndex, block) in document.textBlocks.enumerated() {
                        let pieces = TranslationUnitPlanner.units(from: block)
                        for (pieceIndex, piece) in pieces.enumerated() {
                            units.append(EPUBTranslationUnit(
                                id: "\(document.path)#block-\(blockIndex)#piece-\(pieceIndex)",
                                documentPath: document.path,
                                blockIndex: blockIndex,
                                pieceIndex: pieceIndex,
                                pieceCount: pieces.count,
                                blockKind: block.kind,
                                sourceText: piece
                            ))
                        }
                    }
                }
                guard !units.isEmpty else { throw FileAccessError.invalidEPUB }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                let info = EPUBFileInfo(
                    fileName: url.lastPathComponent,
                    bookTitle: package.bookTitle,
                    byteCount: UInt64(values.fileSize ?? archiveData.count),
                    readingDocumentCount: package.readingDocumentCount,
                    translationUnitCount: units.count,
                    sourceCharacterCount: units.reduce(0) { $0 + $1.sourceText.count },
                    headerDescription: "EPUB package, spine, and XHTML scanned"
                )
                return EPUBTranslationPlan(
                    info: info,
                    packagePath: package.packagePath,
                    documentPaths: package.documents.map(\.path),
                    units: units
                )
            } catch let error as FileAccessError {
                throw error
            } catch {
                throw FileAccessError.readFailed
            }
        }
    }

    func saveAuthorizedTestCopy(from source: URL, to destination: URL) throws -> UInt64 {
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            throw FileAccessError.sourceOverwrite
        }
        guard destination.pathExtension.lowercased() == "epub" else {
            throw FileAccessError.invalidEPUB
        }

        return try withScopedAccess(to: source) {
            try withScopedAccess(to: destination) {
                do {
                    let data = try Data(contentsOf: source, options: [.mappedIfSafe])
                    try data.write(to: destination, options: [.atomic])
                    return UInt64(data.count)
                } catch CocoaError.fileWriteNoPermission {
                    throw FileAccessError.targetNotWritable
                } catch let error as FileAccessError {
                    throw error
                } catch {
                    throw Self.isDiskFull(error) ? FileAccessError.diskSpaceLow : FileAccessError.saveFailed
                }
            }
        }
    }

    func buildTranslatedEPUB(
        at source: URL,
        plan: EPUBTranslationPlan,
        translations: [String]
    ) throws -> Data {
        guard source.pathExtension.lowercased() == "epub" else {
            throw FileAccessError.invalidEPUB
        }
        guard fileManager.fileExists(atPath: source.path) else {
            throw FileAccessError.fileMissing
        }
        return try withScopedAccess(to: source) {
            do {
                let sourceData = try Data(contentsOf: source, options: [.mappedIfSafe])
                return try EPUBRebuilder.rebuild(
                    sourceData: sourceData,
                    plan: plan,
                    translations: translations
                )
            } catch let error as FileAccessError {
                throw error
            } catch {
                throw FileAccessError.rebuildFailed
            }
        }
    }

    func saveTranslatedEPUB(
        from preparedSource: URL,
        originalSource: URL,
        to destination: URL
    ) throws -> UInt64 {
        guard destination.standardizedFileURL != originalSource.standardizedFileURL else {
            throw FileAccessError.sourceOverwrite
        }
        return try saveAuthorizedTestCopy(from: preparedSource, to: destination)
    }

    private func withScopedAccess<T>(to url: URL, operation: () throws -> T) throws -> T {
        let started = scopedAccess.startAccessing(url)
        defer { if started { scopedAccess.stopAccessing(url) } }
        return try operation()
    }

    private static func isDiskFull(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return true }
        let value = error as NSError
        return value.domain == NSPOSIXErrorDomain && value.code == Int(ENOSPC)
    }
}

private struct EPUBDocumentInspection {
    let path: String
    let textBlocks: [EPUBTextBlock]
}

private struct EPUBInspectionResult {
    let bookTitle: String?
    let packagePath: String
    let readingDocumentCount: Int
    let documents: [EPUBDocumentInspection]
}

private enum EPUBPackageInspector {
    static func inspect(archive: EPUBZIPArchive) throws -> EPUBInspectionResult {
        guard let containerData = try archive.data(named: "META-INF/container.xml") else {
            throw FileAccessError.invalidEPUB
        }
        let containerDelegate = ContainerParserDelegate()
        try parseXML(containerData, delegate: containerDelegate)
        guard let opfPath = containerDelegate.packagePath else {
            throw FileAccessError.invalidEPUB
        }
        if archive.entry(named: opfPath).map({ $0.flags & 0x0001 != 0 }) == true {
            throw FileAccessError.unsupportedEncryptedContent
        }
        guard let opfData = try archive.data(named: opfPath) else { throw FileAccessError.invalidEPUB }

        let packageDelegate = PackageParserDelegate()
        try parseXML(opfData, delegate: packageDelegate)
        let documentPaths = packageDelegate.readingDocuments(relativeTo: opfPath)
        guard !documentPaths.isEmpty else { throw FileAccessError.invalidEPUB }
        try EPUBEncryptionInspector.validate(archive: archive, readingDocuments: documentPaths)

        var documents: [EPUBDocumentInspection] = []
        for path in documentPaths {
            if archive.entry(named: path).map({ $0.flags & 0x0001 != 0 }) == true {
                throw FileAccessError.unsupportedEncryptedContent
            }
            guard let documentData = try archive.data(named: path) else {
                throw FileAccessError.invalidEPUB
            }
            let documentDelegate = XHTMLTextBlockParserDelegate()
            try parseXML(documentData, delegate: documentDelegate)
            guard try XHTMLDocumentProcessor.uncoveredVisibleText(in: documentData).isEmpty else {
                throw FileAccessError.uncoveredVisibleText
            }
            documents.append(EPUBDocumentInspection(path: path, textBlocks: documentDelegate.blocks))
        }
        return EPUBInspectionResult(
            bookTitle: packageDelegate.bookTitle,
            packagePath: opfPath,
            readingDocumentCount: documentPaths.count,
            documents: documents
        )
    }

    private static func parseXML(_ data: Data, delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw FileAccessError.invalidEPUB }
    }
}

enum EPUBEncryptionInspector {
    private static let fontAlgorithms: Set<String> = [
        "http://www.idpf.org/2008/embedding",
        "http://ns.adobe.com/pdf/enc#RC",
    ]
    private static let fontExtensions: Set<String> = ["otf", "ttf", "woff", "woff2"]

    static func validate(archive: EPUBZIPArchive, readingDocuments: [String]) throws {
        guard let data = try archive.data(named: "META-INF/encryption.xml") else { return }
        try validate(encryptionData: data, readingDocuments: readingDocuments)
    }

    static func validate(encryptionData data: Data?, readingDocuments: [String]) throws {
        guard let data else { return }
        let delegate = EncryptionParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw FileAccessError.invalidEPUB }

        let reading = Set(readingDocuments.map(normalizedPath))
        for item in delegate.items {
            let path = normalizedPath(item.uri)
            guard reading.contains(path) else { continue }
            let isFontOnly = fontAlgorithms.contains(item.algorithm)
                && fontExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
            if !isFontOnly { throw FileAccessError.unsupportedEncryptedContent }
        }
    }

    private static func normalizedPath(_ value: String) -> String {
        let clean = value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? value
        let decoded = clean.removingPercentEncoding ?? clean
        return String(URL(fileURLWithPath: "/" + decoded).standardizedFileURL.path.drop(while: { $0 == "/" }))
    }
}

private final class EncryptionParserDelegate: NSObject, XMLParserDelegate {
    struct Item { let algorithm: String; let uri: String }
    private var algorithm = ""
    private var uri = ""
    private var insideEncryptedData = false
    private(set) var items: [Item] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "encrypteddata":
            insideEncryptedData = true
            algorithm = ""
            uri = ""
        case "encryptionmethod" where insideEncryptedData:
            algorithm = attributeDict["Algorithm"] ?? attributeDict["algorithm"] ?? ""
        case "cipherreference" where insideEncryptedData:
            uri = attributeDict["URI"] ?? attributeDict["uri"] ?? ""
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "encrypteddata" {
            if !uri.isEmpty { items.append(Item(algorithm: algorithm, uri: uri)) }
            insideEncryptedData = false
        }
    }
}

private final class ContainerParserDelegate: NSObject, XMLParserDelegate {
    private(set) var packagePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName.lowercased() == "rootfile", packagePath == nil {
            packagePath = attributeDict["full-path"]
        }
    }
}

private struct EPUBManifestItem {
    let href: String
    let mediaType: String
    let properties: String
}

private final class PackageParserDelegate: NSObject, XMLParserDelegate {
    private var manifest: [String: EPUBManifestItem] = [:]
    private var spineIDs: [String] = []
    private var capturesTitle = false
    private var titleBuffer = ""
    private(set) var bookTitle: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName.lowercased() {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = EPUBManifestItem(
                    href: href,
                    mediaType: attributeDict["media-type"] ?? "",
                    properties: attributeDict["properties"] ?? ""
                )
            }
        case "itemref":
            if let idref = attributeDict["idref"] { spineIDs.append(idref) }
        case "title":
            if bookTitle == nil {
                capturesTitle = true
                titleBuffer = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturesTitle { titleBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "title", capturesTitle {
            capturesTitle = false
            let value = TranslationUnitPlanner.normalizedText(titleBuffer)
            if !value.isEmpty { bookTitle = value }
        }
    }

    func readingDocuments(relativeTo packagePath: String) -> [String] {
        let ordered = spineIDs.compactMap { manifest[$0] }.filter(Self.isReadingDocument)
        let fallback = manifest.values.filter(Self.isReadingDocument)
        return (ordered.isEmpty ? fallback : ordered).map {
            Self.resolve(href: $0.href, relativeTo: packagePath)
        }
    }

    private static func isReadingDocument(_ item: EPUBManifestItem) -> Bool {
        let type = item.mediaType.lowercased()
        let isDocument = type == "application/xhtml+xml" || type == "text/html"
        let isNavigation = item.properties
            .split(whereSeparator: { $0.isWhitespace })
            .contains(where: { $0.lowercased() == "nav" })
        return isDocument && !isNavigation
    }

    private static func resolve(href: String, relativeTo packagePath: String) -> String {
        let cleanHref = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        let decodedHref = cleanHref.removingPercentEncoding ?? cleanHref
        let directory = (packagePath as NSString).deletingLastPathComponent
        let combined = directory.isEmpty ? decodedHref : directory + "/" + decodedHref
        let standardized = URL(fileURLWithPath: "/" + combined).standardizedFileURL.path
        return String(standardized.drop(while: { $0 == "/" }))
    }
}

private final class XHTMLTextBlockParserDelegate: NSObject, XMLParserDelegate {
    private static let blockElements: Set<String> = [
        "h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "blockquote",
        "figcaption", "td", "th", "dt", "dd", "pre",
    ]
    private static let excludedTextElements: Set<String> = [
        "head", "script", "style", "noscript", "template", "math",
        "img", "picture", "source", "svg", "image", "object", "canvas",
    ]

    private var depth = 0
    private var captureRootDepth: Int?
    private var captureKind = EPUBTextBlockKind.standard
    private var ignoredRootDepth: Int?
    private var excludedTextRootDepth: Int?
    private var buffer = ""
    private(set) var blocks: [EPUBTextBlock] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        if ignoredRootDepth == nil,
           (attributeDict["data-epub-translator-generated"] == "true"
            || attributeDict["data-epub-translator-preserved-original"] == "true") {
            ignoredRootDepth = depth
        }
        guard ignoredRootDepth == nil else { return }
        let element = elementName.lowercased()
        if excludedTextRootDepth == nil, Self.excludedTextElements.contains(element) {
            excludedTextRootDepth = depth
        }
        guard excludedTextRootDepth == nil else { return }
        if captureRootDepth == nil, Self.blockElements.contains(element) {
            captureRootDepth = depth
            captureKind = element == "pre" ? .preformatted : .standard
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if ignoredRootDepth == nil,
           excludedTextRootDepth == nil,
           captureRootDepth != nil { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if ignoredRootDepth == depth {
            ignoredRootDepth = nil
            depth -= 1
            return
        }
        if ignoredRootDepth != nil {
            depth -= 1
            return
        }
        if excludedTextRootDepth == depth {
            excludedTextRootDepth = nil
            depth -= 1
            return
        }
        if excludedTextRootDepth != nil {
            depth -= 1
            return
        }
        if captureRootDepth == depth {
            let text = captureKind == .preformatted
                ? TranslationUnitPlanner.normalizedPreformattedText(buffer)
                : TranslationUnitPlanner.normalizedText(buffer)
            if text.unicodeScalars.contains(where: Self.isTextCharacter) {
                blocks.append(EPUBTextBlock(sourceText: text, kind: captureKind))
            }
            captureRootDepth = nil
            buffer = ""
        }
        depth -= 1
    }

    private static func isTextCharacter(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
             .otherLetter, .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}

struct EPUBZIPEntry {
    let name: String
    let flags: UInt16
    let compressionMethod: UInt16
    let modificationTime: UInt16
    let modificationDate: UInt16
    let crc32: UInt32
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
    let externalFileAttributes: UInt32

    var isDirectory: Bool {
        name.hasSuffix("/")
            || externalFileAttributes & 0x10 != 0
            || (externalFileAttributes >> 16) & 0xF000 == 0x4000
    }
}

struct EPUBZIPArchive {
    private let bytes: Data
    private let entries: [String: EPUBZIPEntry]
    let orderedEntries: [EPUBZIPEntry]

    init(data: Data) throws {
        guard data.count >= 22,
              data.littleEndianUInt32(at: 0) == 0x04034B50 else {
            throw FileAccessError.invalidEPUB
        }
        bytes = data
        orderedEntries = try Self.readCentralDirectory(from: data)
        entries = Dictionary(uniqueKeysWithValues: orderedEntries.map { ($0.name, $0) })
    }

    var fileEntryNames: [String] {
        orderedEntries.filter { !$0.isDirectory }.map(\.name)
    }

    var firstLocalEntryName: String? {
        orderedEntries.min(by: { $0.localHeaderOffset < $1.localHeaderOffset })?.name
    }

    func entry(named rawName: String) -> EPUBZIPEntry? {
        entries[Self.normalizedPath(rawName)]
    }

    func data(named rawName: String) throws -> Data? {
        let name = Self.normalizedPath(rawName)
        guard let entry = entries[name] else { return nil }
        guard entry.flags & 0x0001 == 0 else { throw FileAccessError.invalidEPUB }
        let offset = entry.localHeaderOffset
        guard bytes.littleEndianUInt32(at: offset) == 0x04034B50,
              let nameLength = bytes.littleEndianUInt16(at: offset + 26),
              let extraLength = bytes.littleEndianUInt16(at: offset + 28) else {
            throw FileAccessError.invalidEPUB
        }
        let start = offset + 30 + Int(nameLength) + Int(extraLength)
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count else { throw FileAccessError.invalidEPUB }
        let compressed = bytes.subdata(in: start..<end)
        switch entry.compressionMethod {
        case 0:
            guard compressed.count == entry.uncompressedSize else {
                throw FileAccessError.invalidEPUB
            }
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw FileAccessError.unsupportedEPUBCompression
        }
    }

    func rawCompressedData(for entry: EPUBZIPEntry) throws -> Data {
        guard entry.flags & 0x0001 == 0 else { throw FileAccessError.invalidEPUB }
        let offset = entry.localHeaderOffset
        guard bytes.littleEndianUInt32(at: offset) == 0x04034B50,
              let nameLength = bytes.littleEndianUInt16(at: offset + 26),
              let extraLength = bytes.littleEndianUInt16(at: offset + 28) else {
            throw FileAccessError.invalidEPUB
        }
        let start = offset + 30 + Int(nameLength) + Int(extraLength)
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count else { throw FileAccessError.invalidEPUB }
        return bytes.subdata(in: start..<end)
    }

    private static func readCentralDirectory(from data: Data) throws -> [EPUBZIPEntry] {
        guard let eocdOffset = endOfCentralDirectoryOffset(in: data),
              let totalEntries = data.littleEndianUInt16(at: eocdOffset + 10),
              let centralOffset = data.littleEndianUInt32(at: eocdOffset + 16),
              totalEntries <= 10_000 else {
            throw FileAccessError.invalidEPUB
        }
        var offset = Int(centralOffset)
        var entries: [EPUBZIPEntry] = []
        for _ in 0..<Int(totalEntries) {
            guard data.littleEndianUInt32(at: offset) == 0x02014B50,
                  let flags = data.littleEndianUInt16(at: offset + 8),
                  let method = data.littleEndianUInt16(at: offset + 10),
                  let modificationTime = data.littleEndianUInt16(at: offset + 12),
                  let modificationDate = data.littleEndianUInt16(at: offset + 14),
                  let crc32 = data.littleEndianUInt32(at: offset + 16),
                  let compressedSize = data.littleEndianUInt32(at: offset + 20),
                  let uncompressedSize = data.littleEndianUInt32(at: offset + 24),
                  let nameLength = data.littleEndianUInt16(at: offset + 28),
                  let extraLength = data.littleEndianUInt16(at: offset + 30),
                  let commentLength = data.littleEndianUInt16(at: offset + 32),
                  let externalFileAttributes = data.littleEndianUInt32(at: offset + 38),
                  let localOffset = data.littleEndianUInt32(at: offset + 42),
                  compressedSize != UInt32.max,
                  uncompressedSize != UInt32.max,
                  localOffset != UInt32.max else {
                throw FileAccessError.invalidEPUB
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= data.count,
                  let rawName = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) else {
                throw FileAccessError.invalidEPUB
            }
            let name = normalizedPath(rawName)
            entries.append(EPUBZIPEntry(
                name: name,
                flags: flags,
                compressionMethod: method,
                modificationTime: modificationTime,
                modificationDate: modificationDate,
                crc32: crc32,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localOffset),
                externalFileAttributes: externalFileAttributes
            ))
            offset = nameEnd + Int(extraLength) + Int(commentLength)
        }
        return entries
    }

    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let lowerBound = max(0, data.count - 65_557)
        var offset = data.count - 22
        while offset >= lowerBound {
            if data.littleEndianUInt32(at: offset) == 0x06054B50 { return offset }
            offset -= 1
        }
        return nil
    }

    private static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0, expectedSize <= 64 * 1_024 * 1_024 else {
            throw FileAccessError.invalidEPUB
        }
        if expectedSize == 0 { return Data() }
        var output = Data(count: expectedSize)
        let decoded = output.withUnsafeMutableBytes { outputBuffer in
            compressed.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decoded == expectedSize else { throw FileAccessError.invalidEPUB }
        return output
    }

    private static func normalizedPath(_ rawPath: String) -> String {
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        let isDirectoryEntry = decoded.hasSuffix("/")
        let standardized = URL(fileURLWithPath: "/" + decoded).standardizedFileURL.path
        let normalized = String(standardized.drop(while: { $0 == "/" }))
        if isDirectoryEntry, !normalized.isEmpty, !normalized.hasSuffix("/") {
            return normalized + "/"
        }
        return normalized
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return withUnsafeBytes { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            let low = UInt16(bytes[offset])
            let high = UInt16(bytes[offset + 1]) << 8
            return low | high
        }
    }

    func littleEndianUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return withUnsafeBytes { rawBytes in
            let bytes = rawBytes.bindMemory(to: UInt8.self)
            let byte0 = UInt32(bytes[offset])
            let byte1 = UInt32(bytes[offset + 1]) << 8
            let byte2 = UInt32(bytes[offset + 2]) << 16
            let byte3 = UInt32(bytes[offset + 3]) << 24
            return byte0 | byte1 | byte2 | byte3
        }
    }
}

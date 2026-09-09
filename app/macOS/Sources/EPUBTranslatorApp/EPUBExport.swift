import Compression
import Foundation

private struct EPUBBlockKey: Hashable {
    let documentPath: String
    let blockIndex: Int
}

enum EPUBRebuilder {
    static func rebuild(
        sourceData: Data,
        plan: EPUBTranslationPlan,
        translations: [String]
    ) throws -> Data {
        guard plan.units.count == translations.count else {
            throw FileAccessError.translationMismatch
        }

        let sourceArchive = try EPUBZIPArchive(data: sourceData)
        guard sourceArchive.firstLocalEntryName == "mimetype",
              let mediaType = try sourceArchive.data(named: "mimetype"),
              String(data: mediaType, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                == "application/epub+zip" else {
            throw FileAccessError.invalidEPUB
        }

        let translatedBlocks = try assembleBlocks(plan: plan, translations: translations)
        var replacements: [String: Data] = [:]
        for documentPath in plan.documentPaths {
            let replacementsForDocument = translatedBlocks
                .filter { $0.key.documentPath == documentPath }
                .reduce(into: [Int: String]()) { $0[$1.key.blockIndex] = $1.value }
            if replacementsForDocument.isEmpty { continue }
            guard let sourceDocument = try sourceArchive.data(named: documentPath) else {
                throw FileAccessError.translationMismatch
            }
            replacements[documentPath] = try XHTMLDocumentProcessor.rewrite(
                sourceDocument,
                translatedBlocks: replacementsForDocument
            )
        }

        let rebuilt = try EPUBZIPWriter.rebuild(source: sourceArchive, replacements: replacements)
        try validate(
            rebuiltData: rebuilt,
            sourceArchive: sourceArchive,
            plan: plan,
            translatedBlocks: translatedBlocks
        )
        return rebuilt
    }

    private static func assembleBlocks(
        plan: EPUBTranslationPlan,
        translations: [String]
    ) throws -> [EPUBBlockKey: String] {
        var piecesByBlock: [EPUBBlockKey: [String?]] = [:]
        var kindsByBlock: [EPUBBlockKey: EPUBTextBlockKind] = [:]
        for (unit, rawTranslation) in zip(plan.units, translations) {
            let translation = rawTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translation.isEmpty,
                  unit.pieceCount > 0,
                  unit.pieceIndex >= 0,
                  unit.pieceIndex < unit.pieceCount else {
                throw FileAccessError.translationMismatch
            }
            let key = EPUBBlockKey(documentPath: unit.documentPath, blockIndex: unit.blockIndex)
            var pieces = piecesByBlock[key] ?? Array(repeating: nil, count: unit.pieceCount)
            guard pieces.count == unit.pieceCount,
                  pieces[unit.pieceIndex] == nil,
                  kindsByBlock[key].map({ $0 == unit.blockKind }) ?? true else {
                throw FileAccessError.translationMismatch
            }
            pieces[unit.pieceIndex] = translation
            piecesByBlock[key] = pieces
            kindsByBlock[key] = unit.blockKind
        }

        var blocks: [EPUBBlockKey: String] = [:]
        for (key, pieces) in piecesByBlock {
            guard pieces.allSatisfy({ $0 != nil }), let kind = kindsByBlock[key] else {
                throw FileAccessError.translationMismatch
            }
            blocks[key] = pieces.compactMap { $0 }.joined(separator: kind.translationSeparator)
        }
        return blocks
    }

    private static func validate(
        rebuiltData: Data,
        sourceArchive: EPUBZIPArchive,
        plan: EPUBTranslationPlan,
        translatedBlocks: [EPUBBlockKey: String]
    ) throws {
        let rebuilt = try EPUBZIPArchive(data: rebuiltData)
        guard rebuilt.firstLocalEntryName == "mimetype",
              rebuilt.fileEntryNames.count == sourceArchive.fileEntryNames.count,
              Set(rebuilt.fileEntryNames) == Set(sourceArchive.fileEntryNames),
              let mediaType = try rebuilt.data(named: "mimetype"),
              String(data: mediaType, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                == "application/epub+zip",
              try rebuilt.data(named: plan.packagePath) != nil else {
            throw FileAccessError.rebuildFailed
        }

        let translatedDocumentPaths = Set(plan.documentPaths)
        for resourcePath in sourceArchive.fileEntryNames
            where !translatedDocumentPaths.contains(resourcePath) {
            guard let sourceResource = try sourceArchive.data(named: resourcePath),
                  let rebuiltResource = try rebuilt.data(named: resourcePath),
                  sourceResource == rebuiltResource else {
                throw FileAccessError.rebuildFailed
            }
        }

        for documentPath in plan.documentPaths {
            guard let sourceDocumentData = try sourceArchive.data(named: documentPath),
                  let documentData = try rebuilt.data(named: documentPath),
                  try XHTMLDocumentProcessor.visualElementSignatures(from: documentData)
                    == XHTMLDocumentProcessor.visualElementSignatures(from: sourceDocumentData) else {
                throw FileAccessError.rebuildFailed
            }
            let blocks = try XHTMLDocumentProcessor.blockTexts(from: documentData)
            let expected = translatedBlocks.filter { $0.key.documentPath == documentPath }
            guard blocks.count == expected.count else { throw FileAccessError.rebuildFailed }
            for (key, translation) in expected {
                guard blocks.indices.contains(key.blockIndex),
                      TranslationUnitPlanner.normalizedText(blocks[key.blockIndex])
                        == TranslationUnitPlanner.normalizedText(translation) else {
                    throw FileAccessError.rebuildFailed
                }
            }
        }
    }
}

enum XHTMLDocumentProcessor {
    private static let blockElementNames: Set<String> = [
        "h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "blockquote",
        "figcaption", "td", "th", "dt", "dd", "pre",
    ]
    private static let invisibleElementNames: Set<String> = [
        "head", "script", "style", "noscript", "template", "svg", "math",
    ]
    private static let visualElementNames: Set<String> = [
        "img", "picture", "source", "svg", "image", "object", "canvas",
    ]
    private static let generatedAttribute = "data-epub-translator-generated"
    private static let preservedOriginalAttribute = "data-epub-translator-preserved-original"

    static func blockTexts(from data: Data) throws -> [String] {
        let document = try parse(data)
        return translatableBlocks(in: document).map {
            normalizedBlockText($0)
        }
    }

    static func uncoveredVisibleText(in data: Data) throws -> [String] {
        let document = try parse(data)
        guard let root = document.rootElement(),
              let body = firstElement(named: "body", in: root) else { return [] }
        var result: [String] = []
        collectUncoveredText(from: body, isCovered: false, result: &result)
        return result
    }

    static func visualElementSignatures(from data: Data) throws -> [String] {
        let document = try parse(data)
        guard let root = document.rootElement() else { return [] }
        var signatures: [String] = []
        collectVisualElementSignatures(from: root, result: &signatures)
        return signatures
    }

    static func rewrite(_ data: Data, translatedBlocks: [Int: String]) throws -> Data {
        let document = try parse(data)
        let blocks = translatableBlocks(in: document)
        guard translatedBlocks.keys.allSatisfy(blocks.indices.contains) else {
            throw FileAccessError.translationMismatch
        }
        for (blockIndex, translation) in translatedBlocks.sorted(by: { $0.key < $1.key }) {
            let block = blocks[blockIndex]
            let name = (block.localName ?? block.name ?? "").lowercased()
            let preservedOriginal = name == "pre" ? block.copy() as? XMLElement : nil
            try replaceVisibleText(in: block, with: translation)
            if let preservedOriginal {
                try insertPreservedOriginal(preservedOriginal, after: block)
            }
        }
        return document.xmlData(options: [.nodePreserveAll])
    }

    private static func parse(_ data: Data) throws -> XMLDocument {
        do {
            return try XMLDocument(
                data: data,
                options: [.nodePreserveAll, .nodeLoadExternalEntitiesNever]
            )
        } catch {
            throw FileAccessError.invalidEPUB
        }
    }

    private static func translatableBlocks(in document: XMLDocument) -> [XMLElement] {
        guard let root = document.rootElement() else { return [] }
        var result: [XMLElement] = []
        collectBlocks(from: root, result: &result)
        return result
    }

    private static func collectBlocks(from element: XMLElement, result: inout [XMLElement]) {
        if isGeneratedOrPreserved(element) { return }
        let name = (element.localName ?? element.name ?? "").lowercased()
        if blockElementNames.contains(name) {
            let text = normalizedBlockText(element)
            if text.unicodeScalars.contains(where: isTextCharacter) {
                result.append(element)
            }
            return
        }
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement {
                collectBlocks(from: childElement, result: &result)
            }
        }
    }

    private static func normalizedBlockText(_ element: XMLElement) -> String {
        let name = (element.localName ?? element.name ?? "").lowercased()
        let visibleText = visibleTextContent(of: element)
        if name == "pre" {
            return TranslationUnitPlanner.normalizedPreformattedText(visibleText)
        }
        return TranslationUnitPlanner.normalizedText(visibleText)
    }

    private static func visibleTextContent(of node: XMLNode) -> String {
        var fragments: [String] = []
        collectVisibleTextContent(from: node, result: &fragments)
        return fragments.joined()
    }

    private static func collectVisibleTextContent(from node: XMLNode, result: inout [String]) {
        for child in node.children ?? [] {
            switch child.kind {
            case .text:
                result.append(child.stringValue ?? "")
            case .element:
                guard let element = child as? XMLElement else { continue }
                let name = (element.localName ?? element.name ?? "").lowercased()
                if invisibleElementNames.contains(name) || visualElementNames.contains(name) { continue }
                collectVisibleTextContent(from: element, result: &result)
            default:
                break
            }
        }
    }

    private static func collectVisualElementSignatures(
        from element: XMLElement,
        result: inout [String]
    ) {
        let name = (element.localName ?? element.name ?? "").lowercased()
        if visualElementNames.contains(name) {
            result.append(element.xmlString(options: [.nodePreserveAll]))
            return
        }
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement {
                collectVisualElementSignatures(from: childElement, result: &result)
            }
        }
    }

    private static func insertPreservedOriginal(
        _ original: XMLElement,
        after translatedElement: XMLElement
    ) throws {
        guard let parent = translatedElement.parent as? XMLElement,
              let translatedIndex = parent.children?.firstIndex(where: { $0 === translatedElement }) else {
            throw FileAccessError.rebuildFailed
        }

        let label = XMLElement(name: "p", stringValue: "英文原文（为保留原始排版而附后）")
        label.addAttribute(XMLNode.attribute(
            withName: generatedAttribute,
            stringValue: "true"
        ) as! XMLNode)

        original.addAttribute(XMLNode.attribute(
            withName: preservedOriginalAttribute,
            stringValue: "true"
        ) as! XMLNode)
        let oldClass = original.attribute(forName: "class")?.stringValue ?? ""
        let newClass = [oldClass, "epub-translator-preserved-original"]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if let classAttribute = original.attribute(forName: "class") {
            classAttribute.stringValue = newClass
        } else {
            original.addAttribute(XMLNode.attribute(withName: "class", stringValue: newClass) as! XMLNode)
        }

        parent.insertChild(label, at: translatedIndex + 1)
        parent.insertChild(original, at: translatedIndex + 2)
    }

    private static func firstElement(named targetName: String, in element: XMLElement) -> XMLElement? {
        let name = (element.localName ?? element.name ?? "").lowercased()
        if name == targetName { return element }
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement,
               let match = firstElement(named: targetName, in: childElement) {
                return match
            }
        }
        return nil
    }

    private static func collectUncoveredText(
        from element: XMLElement,
        isCovered: Bool,
        result: inout [String]
    ) {
        let name = (element.localName ?? element.name ?? "").lowercased()
        if invisibleElementNames.contains(name)
            || visualElementNames.contains(name)
            || isGeneratedOrPreserved(element)
            || element.attribute(forName: "hidden") != nil
            || element.attribute(forName: "aria-hidden")?.stringValue?.lowercased() == "true" {
            return
        }
        let covered = isCovered || blockElementNames.contains(name)
        for child in element.children ?? [] {
            switch child.kind {
            case .text where !covered:
                let text = TranslationUnitPlanner.normalizedText(child.stringValue ?? "")
                if text.unicodeScalars.contains(where: isTextCharacter) { result.append(text) }
            case .element:
                if let childElement = child as? XMLElement {
                    collectUncoveredText(from: childElement, isCovered: covered, result: &result)
                }
            default:
                break
            }
        }
    }

    private static func isGeneratedOrPreserved(_ element: XMLElement) -> Bool {
        element.attribute(forName: generatedAttribute)?.stringValue == "true"
            || element.attribute(forName: preservedOriginalAttribute)?.stringValue == "true"
    }

    private static func replaceVisibleText(in element: XMLElement, with translation: String) throws {
        let cleanTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTranslation.isEmpty else { throw FileAccessError.translationMismatch }

        var allTextNodes: [XMLNode] = []
        collectTextNodes(from: element, result: &allTextNodes)
        let meaningfulNodes = allTextNodes.filter {
            !TranslationUnitPlanner.normalizedText($0.stringValue ?? "").isEmpty
        }
        guard !meaningfulNodes.isEmpty else { throw FileAccessError.translationMismatch }

        let weights = meaningfulNodes.map {
            max(1, TranslationUnitPlanner.normalizedText($0.stringValue ?? "").count)
        }
        let totalWeight = max(1, weights.reduce(0, +))
        let characters = Array(cleanTranslation)
        var previousEnd = 0
        var cumulativeWeight = 0

        for node in allTextNodes { node.stringValue = "" }
        for index in meaningfulNodes.indices {
            cumulativeWeight += weights[index]
            let end: Int
            if index == meaningfulNodes.index(before: meaningfulNodes.endIndex) {
                end = characters.count
            } else {
                end = min(
                    characters.count,
                    Int((Double(cumulativeWeight) / Double(totalWeight) * Double(characters.count)).rounded())
                )
            }
            meaningfulNodes[index].stringValue = String(characters[previousEnd..<max(previousEnd, end)])
            previousEnd = max(previousEnd, end)
        }

        guard TranslationUnitPlanner.normalizedText(visibleTextContent(of: element))
                == TranslationUnitPlanner.normalizedText(cleanTranslation) else {
            throw FileAccessError.rebuildFailed
        }
    }

    private static func collectTextNodes(from node: XMLNode, result: inout [XMLNode]) {
        for child in node.children ?? [] {
            switch child.kind {
            case .text:
                result.append(child)
            case .element:
                guard let element = child as? XMLElement else { continue }
                let name = (element.localName ?? element.name ?? "").lowercased()
                if invisibleElementNames.contains(name) || visualElementNames.contains(name) { continue }
                collectTextNodes(from: element, result: &result)
            default:
                break
            }
        }
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

enum EPUBZIPWriter {
    private struct OutputEntry {
        let nameData: Data
        let flags: UInt16
        let method: UInt16
        let modificationTime: UInt16
        let modificationDate: UInt16
        let crc32: UInt32
        let compressedData: Data
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    static func rebuild(source: EPUBZIPArchive, replacements: [String: Data]) throws -> Data {
        var sourceEntries = source.orderedEntries
            .filter { !$0.isDirectory }
            .sorted { $0.localHeaderOffset < $1.localHeaderOffset }
        if let mimetypeIndex = sourceEntries.firstIndex(where: { $0.name == "mimetype" }) {
            let mimetype = sourceEntries.remove(at: mimetypeIndex)
            sourceEntries.insert(mimetype, at: 0)
        }
        guard sourceEntries.first?.name == "mimetype",
              sourceEntries.count <= Int(UInt16.max) else {
            throw FileAccessError.rebuildFailed
        }

        var archiveData = Data()
        var outputEntries: [OutputEntry] = []
        for sourceEntry in sourceEntries {
            guard sourceEntry.flags & 0x0001 == 0,
                  let nameData = sourceEntry.name.data(using: .utf8),
                  nameData.count <= Int(UInt16.max),
                  let localOffset = UInt32(exactly: archiveData.count) else {
                throw FileAccessError.rebuildFailed
            }

            let method: UInt16
            let compressedData: Data
            let uncompressedSize: UInt32
            let crc32: UInt32
            if let replacement = replacements[sourceEntry.name] {
                method = sourceEntry.name == "mimetype" ? 0 : 8
                compressedData = method == 0 ? replacement : try deflate(replacement)
                guard let replacementSize = UInt32(exactly: replacement.count) else {
                    throw FileAccessError.rebuildFailed
                }
                uncompressedSize = replacementSize
                crc32 = CRC32.checksum(replacement)
            } else {
                method = sourceEntry.compressionMethod
                compressedData = try source.rawCompressedData(for: sourceEntry)
                guard let sourceSize = UInt32(exactly: sourceEntry.uncompressedSize) else {
                    throw FileAccessError.rebuildFailed
                }
                uncompressedSize = sourceSize
                crc32 = sourceEntry.crc32
            }
            guard let compressedSize = UInt32(exactly: compressedData.count) else {
                throw FileAccessError.rebuildFailed
            }
            let flags: UInt16 = 0x0800
            let versionNeeded: UInt16 = method == 0 ? 10 : 20

            archiveData.appendLE(UInt32(0x04034B50))
            archiveData.appendLE(versionNeeded)
            archiveData.appendLE(flags)
            archiveData.appendLE(method)
            archiveData.appendLE(sourceEntry.modificationTime)
            archiveData.appendLE(sourceEntry.modificationDate)
            archiveData.appendLE(crc32)
            archiveData.appendLE(compressedSize)
            archiveData.appendLE(uncompressedSize)
            archiveData.appendLE(UInt16(nameData.count))
            archiveData.appendLE(UInt16(0))
            archiveData.append(nameData)
            archiveData.append(compressedData)

            outputEntries.append(OutputEntry(
                nameData: nameData,
                flags: flags,
                method: method,
                modificationTime: sourceEntry.modificationTime,
                modificationDate: sourceEntry.modificationDate,
                crc32: crc32,
                compressedData: compressedData,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
        }

        guard let centralOffset = UInt32(exactly: archiveData.count) else {
            throw FileAccessError.rebuildFailed
        }
        for entry in outputEntries {
            guard let compressedSize = UInt32(exactly: entry.compressedData.count) else {
                throw FileAccessError.rebuildFailed
            }
            let versionNeeded: UInt16 = entry.method == 0 ? 10 : 20
            archiveData.appendLE(UInt32(0x02014B50))
            archiveData.appendLE(UInt16(0x0314))
            archiveData.appendLE(versionNeeded)
            archiveData.appendLE(entry.flags)
            archiveData.appendLE(entry.method)
            archiveData.appendLE(entry.modificationTime)
            archiveData.appendLE(entry.modificationDate)
            archiveData.appendLE(entry.crc32)
            archiveData.appendLE(compressedSize)
            archiveData.appendLE(entry.uncompressedSize)
            archiveData.appendLE(UInt16(entry.nameData.count))
            archiveData.appendLE(UInt16(0))
            archiveData.appendLE(UInt16(0))
            archiveData.appendLE(UInt16(0))
            archiveData.appendLE(UInt16(0))
            archiveData.appendLE(UInt32(0))
            archiveData.appendLE(entry.localHeaderOffset)
            archiveData.append(entry.nameData)
        }

        guard let centralSize = UInt32(exactly: archiveData.count - Int(centralOffset)) else {
            throw FileAccessError.rebuildFailed
        }
        archiveData.appendLE(UInt32(0x06054B50))
        archiveData.appendLE(UInt16(0))
        archiveData.appendLE(UInt16(0))
        archiveData.appendLE(UInt16(outputEntries.count))
        archiveData.appendLE(UInt16(outputEntries.count))
        archiveData.appendLE(centralSize)
        archiveData.appendLE(centralOffset)
        archiveData.appendLE(UInt16(0))
        return archiveData
    }

    private static func deflate(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }
        var capacity = max(128, data.count + data.count / 8 + 128)
        for _ in 0..<5 {
            var output = Data(count: capacity)
            let encoded = output.withUnsafeMutableBytes { outputBuffer in
                data.withUnsafeBytes { inputBuffer in
                    compression_encode_buffer(
                        outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        capacity,
                        inputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if encoded > 0 {
                output.count = encoded
                return output
            }
            capacity *= 2
        }
        throw FileAccessError.rebuildFailed
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var current = UInt32(value)
        for _ in 0..<8 {
            current = current & 1 == 1 ? (current >> 1) ^ 0xEDB88320 : current >> 1
        }
        return current
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ table[index]
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

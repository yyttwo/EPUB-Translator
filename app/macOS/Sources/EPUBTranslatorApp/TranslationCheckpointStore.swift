import CryptoKit
import Foundation

struct TranslationCheckpointRecord: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let sourceFingerprint: String
    let expectedUnitCount: Int
    let provider: ProviderID
    let style: TranslationStyle
    let translations: [String]

    init(
        sourceFingerprint: String,
        expectedUnitCount: Int,
        provider: ProviderID,
        style: TranslationStyle,
        translations: [String]
    ) {
        self.version = Self.currentVersion
        self.sourceFingerprint = sourceFingerprint
        self.expectedUnitCount = expectedUnitCount
        self.provider = provider
        self.style = style
        self.translations = translations
    }

    var isValid: Bool {
        version == Self.currentVersion
            && sourceFingerprint.count == 64
            && expectedUnitCount > 0
            && translations.count <= expectedUnitCount
            && translations.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

enum TranslationSourceFingerprint {
    static func make(plan: EPUBTranslationPlan) -> String {
        var hasher = SHA256()
        update(&hasher, plan.packagePath)
        for path in plan.documentPaths { update(&hasher, path) }
        for unit in plan.units {
            update(&hasher, unit.id)
            update(&hasher, unit.sourceText)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func update(_ hasher: inout SHA256, _ value: String) {
        hasher.update(data: Data(value.utf8))
        hasher.update(data: Data([0]))
    }
}

protocol TranslationCheckpointStoring {
    func load() throws -> TranslationCheckpointRecord?
    func save(_ record: TranslationCheckpointRecord) throws
    func clear() throws
}

final class FileTranslationCheckpointStore: TranslationCheckpointStoring {
    private let explicitFileURL: URL?
    private let fileManager: FileManager

    init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.explicitFileURL = fileURL
        self.fileManager = fileManager
    }

    func load() throws -> TranslationCheckpointRecord? {
        do {
            let url = try checkpointURL()
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            let record = try JSONDecoder().decode(
                TranslationCheckpointRecord.self,
                from: Data(contentsOf: url)
            )
            guard record.isValid else { throw FileAccessError.checkpointRecoveryFailed }
            return record
        } catch let error as FileAccessError {
            throw error
        } catch {
            throw FileAccessError.checkpointRecoveryFailed
        }
    }

    func save(_ record: TranslationCheckpointRecord) throws {
        guard record.isValid else {
            throw FileAccessError.checkpointRecoveryFailed
        }
        do {
            let url = try checkpointURL()
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(record)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: url.path
            )
        } catch let error as FileAccessError {
            throw error
        } catch {
            throw FileAccessError.checkpointRecoveryFailed
        }
    }

    func clear() throws {
        do {
            let url = try checkpointURL()
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            throw FileAccessError.checkpointRecoveryFailed
        }
    }

    private func checkpointURL() throws -> URL {
        if let explicitFileURL { return explicitFileURL }
        let paths = try AppPaths.live(fileManager: fileManager)
        return paths.applicationSupport.appendingPathComponent("translation-checkpoint-v1.json")
    }
}

final class MemoryTranslationCheckpointStore: TranslationCheckpointStoring {
    private var record: TranslationCheckpointRecord?

    func load() throws -> TranslationCheckpointRecord? { record }
    func save(_ record: TranslationCheckpointRecord) throws { self.record = record }
    func clear() throws { record = nil }
}

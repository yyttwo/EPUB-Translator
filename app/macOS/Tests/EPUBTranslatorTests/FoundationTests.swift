import Foundation
import XCTest
@testable import EPUBTranslatorApp

private final class ScopeSpy: SecurityScopedURLAccessing {
    private(set) var started: [URL] = []
    private(set) var stopped: [URL] = []
    var returnsStarted = true

    func startAccessing(_ url: URL) -> Bool {
        started.append(url)
        return returnsStarted
    }

    func stopAccessing(_ url: URL) { stopped.append(url) }
}

private final class MemoryCredentialStore: CredentialStoring {
    private var values: [ProviderID: String] = [:]
    private var persistences: [ProviderID: CredentialPersistence] = [:]

    func saveSecret(
        _ secret: String,
        for provider: ProviderID,
        persistence: CredentialPersistence
    ) throws {
        guard secret.count >= 8 else { throw CredentialStoreError.invalidSecret }
        values[provider] = secret
        persistences[provider] = persistence
    }

    func readSecret(for provider: ProviderID) throws -> String? { values[provider] }
    func hasSecret(for provider: ProviderID) throws -> Bool { values[provider] != nil }
    func persistence(for provider: ProviderID) throws -> CredentialPersistence? { persistences[provider] }
    func deleteSecret(for provider: ProviderID) throws {
        values.removeValue(forKey: provider)
        persistences.removeValue(forKey: provider)
    }
}

private actor CountingSuccessfulTransport: ProviderHTTPTransport {
    private var requestCount = 0
    private var observedTimeouts: [TimeInterval] = []

    func count() -> Int { requestCount }
    func timeouts() -> [TimeInterval] { observedTimeouts }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        observedTimeouts.append(request.timeoutInterval)
        let content = try JSONSerialization.data(
            withJSONObject: ["translation": "这是一次有效的中文翻译。"],
            options: [.sortedKeys]
        )
        let envelope: [String: Any] = [
            "choices": [["message": ["content": String(data: content, encoding: .utf8)!]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["x-request-id": "view-model-test"]
            )!
        )
    }
}

private actor AlwaysTimingOutTransport: ProviderHTTPTransport {
    private var requestCount = 0
    private var observedTimeouts: [TimeInterval] = []

    func count() -> Int { requestCount }
    func timeouts() -> [TimeInterval] { observedTimeouts }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        observedTimeouts.append(request.timeoutInterval)
        throw URLError(.timedOut)
    }
}

private actor CancellableCredentialTransport: ProviderHTTPTransport {
    private var requestCount = 0

    func count() -> Int { requestCount }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let content = try JSONSerialization.data(
            withJSONObject: ["translation": "这是一条有效的验证译文。"]
        )
        let envelope: [String: Any] = [
            "choices": [["message": ["content": String(data: content, encoding: .utf8)!]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}

private actor RejectingCredentialTransport: ProviderHTTPTransport {
    private var requestCount = 0

    func count() -> Int { requestCount }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let data = try JSONSerialization.data(withJSONObject: [
            "error": ["message": "invalid credential"],
        ])
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
        )
    }
}

private actor ResumeAfterMalformedTransport: ProviderHTTPTransport {
    private var requestCount = 0

    func count() -> Int { requestCount }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let content: String
        if (4...6).contains(requestCount) {
            content = #"{"unexpected":"temporary malformed result"}"#
        } else {
            content = #"{"translation":"这是一次有效的中文翻译。"}"#
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": content]]],
        ])
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["x-request-id": "resume-test-\(requestCount)"]
            )!
        )
    }
}

@MainActor
private final class FixedTranslatedEPUBSavePanel: TranslatedEPUBSavePanelPresenting {
    let destination: URL?

    init(destination: URL?) {
        self.destination = destination
    }

    func destinationURL(defaultFileName: String, initialDirectory: URL?) -> URL? {
        destination
    }
}

final class FileAccessTests: XCTestCase {
    func testEPUBReadStartsAndStopsSecurityScope() throws {
        let source = try makeFixtureInSandbox()
        defer { try? FileManager.default.removeItem(at: source) }
        let scope = ScopeSpy()
        let service = EPUBFileAccessService(scopedAccess: scope)

        let info = try service.inspectSelectedEPUB(at: source)

        XCTAssertTrue(info.fileName.hasPrefix("stage-1-self-authored-"))
        XCTAssertEqual(info.bookTitle, "Stage One Self-Authored Book")
        XCTAssertEqual(info.readingDocumentCount, 1)
        XCTAssertEqual(info.translationUnitCount, 4)
        XCTAssertGreaterThan(info.sourceCharacterCount, 100)
        XCTAssertEqual(scope.started, [source])
        XCTAssertEqual(scope.stopped, [source])
    }

    func testTranslationUnitsCanBeReloadedForCloudExecution() throws {
        let source = try makeFixtureInSandbox()
        defer { try? FileManager.default.removeItem(at: source) }
        let units = try EPUBFileAccessService().translationUnits(at: source)
        XCTAssertEqual(units.count, 4)
        XCTAssertTrue(units.allSatisfy { !$0.isEmpty })
    }

    func testTranslatedEPUBRebuildPreservesInlineMarkupAndCanBeReopened() throws {
        let source = try makeFixtureInSandbox()
        defer { try? FileManager.default.removeItem(at: source) }
        let originalData = try Data(contentsOf: source)
        let service = EPUBFileAccessService()
        let plan = try service.loadTranslationPlan(at: source)
        let translations = [
            "第一章",
            "这是第一段完整的中文译文。",
            "这一段保留强调文字的结构。",
            "这个链接仍然指向第一章。",
        ]

        let outputData = try service.buildTranslatedEPUB(
            at: source,
            plan: plan,
            translations: translations
        )
        XCTAssertNotEqual(outputData, originalData)
        XCTAssertEqual(try Data(contentsOf: source), originalData)

        let sourceArchive = try EPUBZIPArchive(data: originalData)
        let outputArchive = try EPUBZIPArchive(data: outputData)
        XCTAssertEqual(outputArchive.firstLocalEntryName, "mimetype")
        XCTAssertEqual(Set(outputArchive.fileEntryNames), Set(sourceArchive.fileEntryNames))
        XCTAssertFalse(outputArchive.orderedEntries.contains { $0.name == "META-INF" })
        XCTAssertFalse(outputArchive.orderedEntries.contains { $0.name == "EPUB" })
        XCTAssertTrue(outputArchive.fileEntryNames.contains("META-INF/container.xml"))
        XCTAssertTrue(outputArchive.fileEntryNames.contains("EPUB/chapter1.xhtml"))
        let sourceCover = try XCTUnwrap(try sourceArchive.data(named: "EPUB/cover.svg"))
        let outputCover = try XCTUnwrap(try outputArchive.data(named: "EPUB/cover.svg"))
        XCTAssertEqual(outputCover, sourceCover)
        let packageData = try XCTUnwrap(try outputArchive.data(named: "EPUB/content.opf"))
        let package = try XCTUnwrap(String(data: packageData, encoding: .utf8))
        XCTAssertTrue(package.contains("properties=\"cover-image\""))
        let chapterData = try XCTUnwrap(try outputArchive.data(named: "EPUB/chapter1.xhtml"))
        let chapter = try XCTUnwrap(String(data: chapterData, encoding: .utf8))
        XCTAssertTrue(chapter.contains("<em"))
        XCTAssertTrue(chapter.contains("href=\"#chapter-one\""))
        XCTAssertTrue(chapter.contains("id=\"chapter-one\""))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("translated-\(UUID().uuidString).epub")
        try outputData.write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let reopened = try service.translationUnits(at: outputURL)
        XCTAssertEqual(
            reopened.map(TranslationUnitPlanner.normalizedText),
            translations.map(TranslationUnitPlanner.normalizedText)
        )
    }

    func testPreformattedTextIsTranslatedCountedAndOriginalLayoutIsPreserved() throws {
        let originalPre = "Project Gutenberg notice line one.\nLine two remains aligned.\n\nEnd notice and license terms."
        let source = try makeFixtureAppendingToChapter("<pre class=\"legal\">\(originalPre)</pre>")
        defer { try? FileManager.default.removeItem(at: source) }
        let sourceData = try Data(contentsOf: source)
        let service = EPUBFileAccessService()
        let plan = try service.loadTranslationPlan(at: source)
        let preformattedUnits = plan.units.filter { $0.blockKind == .preformatted }

        XCTAssertEqual(preformattedUnits.count, 2)
        XCTAssertEqual(plan.info.translationUnitCount, 6)
        XCTAssertTrue(preformattedUnits.contains { $0.sourceText.contains("Project Gutenberg") })
        XCTAssertTrue(preformattedUnits.contains { $0.sourceText.contains("license terms") })

        let translations = plan.units.map { unit in
            unit.blockKind == .preformatted
                ? "预格式正文第\(unit.pieceIndex + 1)部分"
                : "普通正文第\(unit.blockIndex + 1)部分"
        }
        let outputData = try service.buildTranslatedEPUB(
            at: source,
            plan: plan,
            translations: translations
        )
        let sourceArchive = try EPUBZIPArchive(data: sourceData)
        let outputArchive = try EPUBZIPArchive(data: outputData)
        XCTAssertEqual(
            try outputArchive.data(named: "EPUB/cover.svg"),
            try sourceArchive.data(named: "EPUB/cover.svg")
        )

        let chapterData = try XCTUnwrap(try outputArchive.data(named: "EPUB/chapter1.xhtml"))
        let chapter = try XCTUnwrap(String(data: chapterData, encoding: .utf8))
        let translatedRange = try XCTUnwrap(chapter.range(of: "预格式正文第1部分"))
        let originalRange = try XCTUnwrap(chapter.range(of: originalPre))
        XCTAssertLessThan(translatedRange.lowerBound, originalRange.lowerBound)
        XCTAssertTrue(chapter.contains("英文原文（为保留原始排版而附后）"))
        XCTAssertTrue(chapter.contains("data-epub-translator-preserved-original"))

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("preformatted-translated-\(UUID().uuidString).epub")
        try outputData.write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let reopenedPlan = try service.loadTranslationPlan(at: outputURL)
        XCTAssertEqual(reopenedPlan.info.translationUnitCount, plan.info.translationUnitCount)
        XCTAssertFalse(reopenedPlan.units.contains { $0.sourceText.contains("Project Gutenberg") })
    }

    func testBodyImagesAndInlineSVGSurviveTranslationUnchanged() throws {
        let markup = """
        <figure id="illustrated-scene"><picture><source srcset="cover.svg" type="image/svg+xml"/><img src="cover.svg" alt="Original illustration" width="320" height="240"/></picture><figcaption>An illustrated scene remains in this chapter.</figcaption></figure>
        <p>Text beside an inline image.<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><title>Original vector image</title><circle cx="10" cy="10" r="8" fill="#f90"/></svg></p>
        """
        let source = try makeFixtureAppendingToChapter(markup)
        defer { try? FileManager.default.removeItem(at: source) }
        let sourceData = try Data(contentsOf: source)
        let service = EPUBFileAccessService()
        let plan = try service.loadTranslationPlan(at: source)
        XCTAssertEqual(plan.info.translationUnitCount, 6)
        XCTAssertFalse(plan.units.contains { $0.sourceText.contains("Original vector image") })

        let translations = plan.units.indices.map { "正文中文译文第\($0 + 1)段。" }
        let outputData = try service.buildTranslatedEPUB(
            at: source,
            plan: plan,
            translations: translations
        )
        let sourceArchive = try EPUBZIPArchive(data: sourceData)
        let outputArchive = try EPUBZIPArchive(data: outputData)
        XCTAssertEqual(
            try outputArchive.data(named: "EPUB/cover.svg"),
            try sourceArchive.data(named: "EPUB/cover.svg")
        )
        let sourceChapter = try XCTUnwrap(try sourceArchive.data(named: "EPUB/chapter1.xhtml"))
        let outputChapter = try XCTUnwrap(try outputArchive.data(named: "EPUB/chapter1.xhtml"))
        XCTAssertEqual(
            try XHTMLDocumentProcessor.visualElementSignatures(from: outputChapter),
            try XHTMLDocumentProcessor.visualElementSignatures(from: sourceChapter)
        )
    }

    func testExternalAcceptanceEPUBCanBeRebuiltWithAllVisualResourcesPreserved() throws {
        guard let sourcePath = ProcessInfo.processInfo.environment["EPUB_TRANSLATOR_ACCEPTANCE_EPUB"] else {
            throw XCTSkip("External acceptance EPUB was not supplied")
        }
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw XCTSkip("External acceptance EPUB was not supplied")
        }
        let source = URL(fileURLWithPath: sourcePath)
        let sourceData = try Data(contentsOf: source, options: [.mappedIfSafe])
        let service = EPUBFileAccessService()
        let plan = try service.loadTranslationPlan(at: source)
        XCTAssertGreaterThan(plan.info.translationUnitCount, 0)

        let technicalOnlyUnits = plan.units.filter {
            TranslationPassThroughPolicy.shouldPreserve($0.sourceText)
        }
        XCTAssertFalse(
            technicalOnlyUnits.isEmpty,
            "Acceptance EPUB should exercise locally preserved technical-only blocks"
        )

        let translations = plan.units.enumerated().map { index, unit in
            TranslationPassThroughPolicy.shouldPreserve(unit.sourceText)
                ? unit.sourceText
                : "验收中文译文第\(index + 1)段。"
        }
        let outputData = try service.buildTranslatedEPUB(
            at: source,
            plan: plan,
            translations: translations
        )

        let sourceArchive = try EPUBZIPArchive(data: sourceData)
        let outputArchive = try EPUBZIPArchive(data: outputData)
        XCTAssertEqual(Set(outputArchive.fileEntryNames), Set(sourceArchive.fileEntryNames))
        XCTAssertEqual(outputArchive.firstLocalEntryName, "mimetype")

        let visualExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "svg", "avif", "bmp"]
        let visualResources = sourceArchive.fileEntryNames.filter {
            visualExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
                && !plan.documentPaths.contains($0)
        }
        XCTAssertFalse(visualResources.isEmpty)
        for resource in visualResources {
            XCTAssertEqual(
                try outputArchive.data(named: resource),
                try sourceArchive.data(named: resource),
                "A cover or in-book image changed during EPUB rebuild"
            )
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-acceptance-\(UUID().uuidString).epub")
        try outputData.write(to: outputURL, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let reopened = try service.loadTranslationPlan(at: outputURL)
        XCTAssertEqual(reopened.info.translationUnitCount, plan.info.translationUnitCount)
        for unit in technicalOnlyUnits {
            XCTAssertTrue(
                reopened.units.contains { $0.sourceText == unit.sourceText },
                "A technical-only block was not preserved in the rebuilt EPUB"
            )
        }
    }

    func testVisibleTextOutsideSupportedBlocksStopsBeforeTranslation() throws {
        let source = try makeFixtureAppendingToChapter(
            "<div>Visible prose outside a supported text block must never be skipped.</div>"
        )
        defer { try? FileManager.default.removeItem(at: source) }
        XCTAssertThrowsError(try EPUBFileAccessService().loadTranslationPlan(at: source)) { error in
            XCTAssertEqual(error as? FileAccessError, .uncoveredVisibleText)
        }
    }

    func testTranslatedEPUBRejectsMismatchedResultsAndSourceOverwrite() throws {
        let source = try makeFixtureInSandbox()
        defer { try? FileManager.default.removeItem(at: source) }
        let service = EPUBFileAccessService()
        let plan = try service.loadTranslationPlan(at: source)
        XCTAssertThrowsError(try service.buildTranslatedEPUB(
            at: source,
            plan: plan,
            translations: ["只有一个译文"]
        )) { error in
            XCTAssertEqual(error as? FileAccessError, .translationMismatch)
        }

        XCTAssertThrowsError(try service.saveTranslatedEPUB(
            from: source,
            originalSource: source,
            to: source
        )) { error in
            XCTAssertEqual(error as? FileAccessError, .sourceOverwrite)
        }
    }

    @MainActor
    func testViewModelValidatesBeforeSavingThenTranslatesEveryUnit() async throws {
        let source = try makeFixtureInSandbox()
        defer { try? FileManager.default.removeItem(at: source) }
        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.flow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ProviderPreferenceStore(defaults: defaults)
        let credentials = MemoryCredentialStore()
        let transport = CountingSuccessfulTransport()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("view-model-translated-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: output) }
        let model = AppViewModel(
            credentials: credentials,
            preferences: preferences,
            providerTransport: transport,
            savePanel: FixedTranslatedEPUBSavePanel(destination: output)
        )

        model.inspectEPUB(at: source)
        model.apiEntryProvider = .qwen
        model.apiKeyInput = "FAKE_TEST_KEY_QWEN_123456"
        model.saveEnteredAPI()
        try await waitUntil { !model.providerBusy }
        XCTAssertEqual(model.credentialState(for: .qwen), .configured)
        let requestsAfterValidation = await transport.count()
        XCTAssertEqual(requestsAfterValidation, 1)

        model.startTranslation()
        try await waitUntil { !model.isTranslating }
        try await waitUntil { model.savedTranslatedEPUBURL != nil }
        XCTAssertEqual(model.completedTranslationUnits, 4)
        XCTAssertEqual(model.translationPercentage, 100)
        XCTAssertEqual(model.translatedUnitResults.count, 4)
        let requestsAfterTranslation = await transport.count()
        XCTAssertEqual(requestsAfterTranslation, 5)
        XCTAssertEqual(model.translationRunState, .completed)
        XCTAssertEqual(model.savedTranslatedEPUBURL, output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try EPUBFileAccessService().translationUnits(at: output).count, 4)
    }

    @MainActor
    func testViewModelContinuesFromFailedUnitWithoutRetranslatingCompletedUnits() async throws {
        let source = try makeFixtureInSandbox()
        defer { try? FileManager.default.removeItem(at: source) }
        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.resume.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentialStore()
        let transport = ResumeAfterMalformedTransport()
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-translated-\(UUID().uuidString).epub")
        defer { try? FileManager.default.removeItem(at: output) }
        let checkpointURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-checkpoint-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: checkpointURL) }
        let model = AppViewModel(
            credentials: credentials,
            preferences: ProviderPreferenceStore(defaults: defaults),
            providerTransport: transport,
            savePanel: FixedTranslatedEPUBSavePanel(destination: output),
            checkpointStore: FileTranslationCheckpointStore(fileURL: checkpointURL)
        )

        model.inspectEPUB(at: source)
        model.apiEntryProvider = .qwen
        model.apiKeyInput = "FAKE_TEST_KEY_QWEN_RESUME_123456"
        model.saveEnteredAPI()
        try await waitUntil { !model.providerBusy }

        model.startTranslation()
        try await waitUntil { !model.isTranslating }
        XCTAssertEqual(model.completedTranslationUnits, 2)
        XCTAssertEqual(model.translatedUnitResults.count, 2)
        XCTAssertTrue(model.canResumeTranslation)
        XCTAssertEqual(model.activeError?.code, "PROVIDER_MALFORMED_RESPONSE")
        XCTAssertEqual(model.activeError?.primaryAction, .retryCurrent)
        XCTAssertEqual(model.activeError?.context.completedUnits, 2)
        XCTAssertEqual(model.activeError?.context.totalUnits, 4)
        let requestsAtFailure = await transport.count()
        XCTAssertEqual(requestsAtFailure, 6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: checkpointURL.path))

        let restoredModel = AppViewModel(
            credentials: credentials,
            preferences: ProviderPreferenceStore(defaults: defaults),
            providerTransport: transport,
            savePanel: FixedTranslatedEPUBSavePanel(destination: output),
            checkpointStore: FileTranslationCheckpointStore(fileURL: checkpointURL)
        )
        restoredModel.inspectEPUB(at: source)
        XCTAssertEqual(restoredModel.completedTranslationUnits, 2)
        XCTAssertEqual(restoredModel.translatedUnitResults.count, 2)
        XCTAssertTrue(restoredModel.canResumeTranslation)
        XCTAssertTrue(restoredModel.statusMessage.contains("已恢复本地进度"))

        restoredModel.startTranslation()
        try await waitUntil { !restoredModel.isTranslating }
        try await waitUntil { restoredModel.savedTranslatedEPUBURL != nil }
        XCTAssertEqual(restoredModel.completedTranslationUnits, 4)
        XCTAssertEqual(restoredModel.translatedUnitResults.count, 4)
        XCTAssertFalse(restoredModel.canResumeTranslation)
        let requestsAfterResume = await transport.count()
        XCTAssertEqual(requestsAfterResume, 8)
        XCTAssertEqual(try EPUBFileAccessService().translationUnits(at: output).count, 4)
        XCTAssertFalse(FileManager.default.fileExists(atPath: checkpointURL.path))
    }

    func testInvalidZIPWithEPUBExtensionIsRejected() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("invalid-\(UUID().uuidString).epub")
        try Data([0x50, 0x4B, 0x03, 0x04, 0x01]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        XCTAssertThrowsError(try EPUBFileAccessService().inspectSelectedEPUB(at: source)) { error in
            XCTAssertEqual(error as? FileAccessError, .invalidEPUB)
        }
    }

    func testTranslationUnitPlannerBoundsLongBlocksAtSentenceBoundaries() {
        let sentence = String(repeating: "A useful sentence contains enough context. ", count: 80)
        let units = TranslationUnitPlanner.units(from: [sentence, "A second paragraph."])
        XCTAssertGreaterThan(units.count, 2)
        XCTAssertTrue(units.allSatisfy { !$0.isEmpty && $0.count <= 1_200 })
        XCTAssertEqual(units.last, "A second paragraph.")
    }

    func testCheckpointStoreIsAtomicPrivateAndContainsNoSourcePathOrCredential() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("checkpoint-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("translation-checkpoint-v1.json")
        let store = FileTranslationCheckpointStore(fileURL: url)
        let privatePath = ["", "Users", "example-user", "Books", "Private.epub"]
            .joined(separator: "/")
        let fakeKey = "sk-" + String(repeating: "A", count: 24)
        let record = TranslationCheckpointRecord(
            sourceFingerprint: String(repeating: "a", count: 64),
            expectedUnitCount: 4,
            provider: .qwen,
            style: .fluent,
            translations: ["第一段译文。", "第二段译文。"]
        )

        try store.save(record)
        XCTAssertEqual(try store.load(), record)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains(privatePath))
        XCTAssertFalse(raw.contains(fakeKey))
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
        try store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSourceFingerprintIsStableAndChangesWithBookText() throws {
        let source = try makeFixtureInSandbox()
        defer { try? FileManager.default.removeItem(at: source) }
        let plan = try EPUBFileAccessService().loadTranslationPlan(at: source)
        let first = TranslationSourceFingerprint.make(plan: plan)
        let second = TranslationSourceFingerprint.make(plan: plan)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
        let changedPlan = EPUBTranslationPlan(
            info: plan.info,
            packagePath: plan.packagePath,
            documentPaths: plan.documentPaths,
            units: plan.units.enumerated().map { index, unit in
                EPUBTranslationUnit(
                    id: unit.id,
                    documentPath: unit.documentPath,
                    blockIndex: unit.blockIndex,
                    pieceIndex: unit.pieceIndex,
                    pieceCount: unit.pieceCount,
                    blockKind: unit.blockKind,
                    sourceText: index == 0 ? unit.sourceText + " changed" : unit.sourceText
                )
            }
        )
        XCTAssertNotEqual(first, TranslationSourceFingerprint.make(plan: changedPlan))
    }

    func testTranslationTimeEstimateUsesBookUnitsCharactersAndProvider() {
        let info = EPUBFileInfo(
            fileName: "book.epub",
            bookTitle: "Book",
            byteCount: 1_024,
            readingDocumentCount: 10,
            translationUnitCount: 120,
            sourceCharacterCount: 60_000,
            headerDescription: "verified"
        )
        let qwen = TranslationTimeEstimator.estimatedSeconds(for: info, provider: .qwen)
        let deepSeek = TranslationTimeEstimator.estimatedSeconds(for: info, provider: .deepSeek)
        XCTAssertGreaterThan(qwen, 0)
        XCTAssertGreaterThan(deepSeek, qwen)
        XCTAssertTrue(TranslationTimeEstimator.displayText(seconds: qwen).contains("约"))
    }

    func testInvalidExtensionIsRejectedBeforeRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-an-epub.txt")
        XCTAssertThrowsError(try EPUBFileAccessService().inspectSelectedEPUB(at: url)) { error in
            XCTAssertEqual(error as? FileAccessError, .invalidEPUB)
        }
    }

    func testSaveCopyPreservesBytesAndNeverOverwritesSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.epub")
        let destination = root.appendingPathComponent("output.epub")
        let bytes = Data([0x50, 0x4B, 0x03, 0x04, 0x10, 0x20])
        try bytes.write(to: source)
        let scope = ScopeSpy()
        let service = EPUBFileAccessService(scopedAccess: scope)

        XCTAssertEqual(try service.saveAuthorizedTestCopy(from: source, to: destination), UInt64(bytes.count))
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        XCTAssertThrowsError(try service.saveAuthorizedTestCopy(from: source, to: source)) { error in
            XCTAssertEqual(error as? FileAccessError, .sourceOverwrite)
        }
        XCTAssertEqual(scope.started.count, 2)
        XCTAssertEqual(scope.stopped.count, 2)
    }

    func testMissingFileMapsToUnderstandableError() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("moved.epub")
        XCTAssertThrowsError(try EPUBFileAccessService().inspectSelectedEPUB(at: url)) { error in
            XCTAssertEqual(error as? FileAccessError, .fileMissing)
        }
    }

    @MainActor
    func testStartupDoesNotValidateAndFailedReplacementPreservesPreviousKey() async throws {
        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.replace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentialStore()
        let original = "FAKE_TEST_ORIGINAL_KEY_\(UUID().uuidString)"
        try credentials.saveSecret(original, for: .qwen, persistence: .sessionOnly)
        let transport = RejectingCredentialTransport()
        let model = AppViewModel(
            credentials: credentials,
            preferences: ProviderPreferenceStore(defaults: defaults),
            providerTransport: transport
        )

        XCTAssertEqual(model.credentialState(for: .qwen), .configured)
        let startupRequests = await transport.count()
        XCTAssertEqual(startupRequests, 0, "启动时不得发起服务商请求")

        model.apiEntryProvider = .qwen
        model.apiKeyInput = "FAKE_TEST_REJECTED_KEY_\(UUID().uuidString)"
        model.validateAndSaveEnteredAPI()
        try await waitUntil { !model.providerBusy }

        let replacementRequests = await transport.count()
        XCTAssertEqual(replacementRequests, 1)
        XCTAssertEqual(try credentials.readSecret(for: .qwen), original)
        XCTAssertEqual(model.credentialState(for: .qwen), .configured)
        XCTAssertTrue(model.apiManagerMessage.contains("原有 API Key 未被替换"))
    }

    @MainActor
    func testRevalidationKeepsStoredCredentialVisibleWhileRequestIsRunning() async throws {
        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.revalidate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentialStore()
        try credentials.saveSecret(
            "FAKE_TEST_REVALIDATION_KEY_\(UUID().uuidString)",
            for: .qwen,
            persistence: .sessionOnly
        )
        let transport = CountingSuccessfulTransport()
        let model = AppViewModel(
            credentials: credentials,
            preferences: ProviderPreferenceStore(defaults: defaults),
            providerTransport: transport
        )

        XCTAssertTrue(model.hasStoredCredential(for: .qwen))
        XCTAssertEqual(model.credentialState(for: .qwen), .configured)

        model.validateCredential(for: .qwen)

        XCTAssertTrue(model.providerBusy)
        XCTAssertEqual(model.credentialState(for: .qwen), .validating)
        XCTAssertTrue(
            model.hasStoredCredential(for: .qwen),
            "重新验证期间，已保存的 API 行和操作按钮必须继续显示"
        )
        XCTAssertEqual(model.credentialPersistence(for: .qwen), .sessionOnly)

        try await waitUntil { !model.providerBusy }
        let requestCount = await transport.count()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(model.credentialState(for: .qwen), .configured)
        XCTAssertTrue(model.hasStoredCredential(for: .qwen))
    }

    @MainActor
    func testCredentialValidationUsesFifteenSecondTimeoutWithoutAutomaticRetry() async throws {
        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.validation-timeout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = AlwaysTimingOutTransport()
        let model = AppViewModel(
            credentials: MemoryCredentialStore(),
            preferences: ProviderPreferenceStore(defaults: defaults),
            providerTransport: transport
        )
        model.apiEntryProvider = .qwen
        model.apiKeyInput = "FAKE_TEST_TIMEOUT_KEY_\(UUID().uuidString)"

        model.validateAndSaveEnteredAPI()
        try await waitUntil { !model.providerBusy }

        let requestCount = await transport.count()
        let timeouts = await transport.timeouts()
        XCTAssertEqual(requestCount, 1, "API 验证超时后不应进行长时间自动重试")
        XCTAssertEqual(timeouts, [15])
        XCTAssertEqual(model.credentialState(for: .qwen), .failed)
        XCTAssertEqual(model.activeError?.code, "PROVIDER_TIMEOUT")
    }

    @MainActor
    func testCancellingCredentialValidationRestoresSavedCredentialImmediately() async throws {
        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.validation-cancel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = MemoryCredentialStore()
        let original = "FAKE_TEST_CANCELLABLE_KEY_\(UUID().uuidString)"
        try credentials.saveSecret(original, for: .qwen, persistence: .sessionOnly)
        let transport = CancellableCredentialTransport()
        let model = AppViewModel(
            credentials: credentials,
            preferences: ProviderPreferenceStore(defaults: defaults),
            providerTransport: transport
        )

        model.validateCredential(for: .qwen)
        for _ in 0..<100 {
            if await transport.count() == 1 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        model.cancelCredentialValidation()
        try await waitUntil { !model.providerBusy }

        let requestCount = await transport.count()
        XCTAssertEqual(requestCount, 1)
        XCTAssertNil(model.validatingProvider)
        XCTAssertEqual(model.credentialState(for: .qwen), .configured)
        XCTAssertTrue(model.hasStoredCredential(for: .qwen))
        XCTAssertEqual(try credentials.readSecret(for: .qwen), original)
        XCTAssertTrue(model.apiManagerMessage.contains("已取消 Qwen 验证"))
    }

    private func makeFixtureInSandbox() throws -> URL {
        let encoded = "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"
        guard let data = Data(base64Encoded: encoded) else {
            throw FileAccessError.invalidEPUB
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-1-self-authored-\(UUID().uuidString).epub")
        try data.write(to: url)
        return url
    }

    private func makeFixtureAppendingToChapter(_ markup: String) throws -> URL {
        let url = try makeFixtureInSandbox()
        let sourceData = try Data(contentsOf: url)
        let archive = try EPUBZIPArchive(data: sourceData)
        let chapterData = try XCTUnwrap(try archive.data(named: "EPUB/chapter1.xhtml"))
        let chapter = try XCTUnwrap(String(data: chapterData, encoding: .utf8))
        guard chapter.contains("</body>") else { throw FileAccessError.invalidEPUB }
        let changed = chapter.replacingOccurrences(
            of: "</body>",
            with: "\(markup)</body>"
        )
        let rebuilt = try EPUBZIPWriter.rebuild(
            source: archive,
            replacements: ["EPUB/chapter1.xhtml": Data(changed.utf8)]
        )
        try rebuilt.write(to: url, options: [.atomic])
        return url
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 3,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for asynchronous state")
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

final class APIManagerCredentialTests: XCTestCase {
    func testQwenAndDeepSeekAddReplaceAndDeleteWithinSession() throws {
        let first = SessionCredentialStore()
        for provider in ProviderID.allCases {
            let initial = "FAKE_TEST_SECRET_\(provider.rawValue)_\(UUID().uuidString)"
            let replacement = "FAKE_TEST_SECRET_REPLACEMENT_\(provider.rawValue)_\(UUID().uuidString)"
            try first.saveSecret(initial, for: provider)
            XCTAssertEqual(try first.readSecret(for: provider), initial)
            try first.saveSecret(replacement, for: provider)
            XCTAssertEqual(try first.readSecret(for: provider), replacement)

            try first.deleteSecret(for: provider)
            XCTAssertNil(try first.readSecret(for: provider))
        }
    }

    func testProviderValuesAreIndependentAndFreshSessionIsEmpty() throws {
        let store = SessionCredentialStore()
        try store.saveSecret("FAKE_TEST_SECRET_QWEN", for: .qwen)
        XCTAssertTrue(try store.hasSecret(for: .qwen))
        XCTAssertFalse(try store.hasSecret(for: .deepSeek))
        let freshSession = SessionCredentialStore()
        XCTAssertFalse(try freshSession.hasSecret(for: .qwen))
        XCTAssertFalse(try freshSession.hasSecret(for: .deepSeek))
    }

    @MainActor
    func testDefaultAppCredentialStoreUsesOnlyCurrentSession() async throws {
        let firstDefaultsSuite = "com.example.EPUBTranslatorAppStore.Dev.tests.session-first.\(UUID().uuidString)"
        let secondDefaultsSuite = "com.example.EPUBTranslatorAppStore.Dev.tests.session-second.\(UUID().uuidString)"
        let firstDefaults = UserDefaults(suiteName: firstDefaultsSuite)!
        let secondDefaults = UserDefaults(suiteName: secondDefaultsSuite)!
        defer {
            firstDefaults.removePersistentDomain(forName: firstDefaultsSuite)
            secondDefaults.removePersistentDomain(forName: secondDefaultsSuite)
        }

        let first = AppViewModel(
            preferences: ProviderPreferenceStore(defaults: firstDefaults),
            providerTransport: CountingSuccessfulTransport()
        )
        first.apiEntryProvider = .qwen
        first.apiKeyInput = "FAKE_SESSION_ONLY_KEY_\(UUID().uuidString)"
        first.validateAndSaveEnteredAPI()
        for _ in 0..<300 where first.providerBusy {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(first.providerBusy)
        XCTAssertEqual(first.credentialState(for: .qwen), .configured)
        XCTAssertEqual(first.credentialPersistence(for: .qwen), .sessionOnly)

        let restarted = AppViewModel(
            preferences: ProviderPreferenceStore(defaults: secondDefaults),
            providerTransport: CountingSuccessfulTransport()
        )
        XCTAssertEqual(restarted.credentialState(for: .qwen), .notConfigured)
        XCTAssertFalse(restarted.hasStoredCredential(for: .qwen))
        XCTAssertNil(restarted.activeError)
    }

}

final class SecurityAndIdentityTests: XCTestCase {
    func testUserEnteredProviderNamesAreRecognized() {
        XCTAssertEqual(ProviderID(userEnteredName: "Qwen"), .qwen)
        XCTAssertEqual(ProviderID(userEnteredName: "通义千问"), .qwen)
        XCTAssertEqual(ProviderID(userEnteredName: "Deep Seek"), .deepSeek)
        XCTAssertEqual(ProviderID(userEnteredName: "深度求索"), .deepSeek)
        XCTAssertNil(ProviderID(userEnteredName: "Unknown API"))
    }

    func testSecretRedaction() {
        let secret = "FAKE_TEST_SECRET_RUNTIME_123456"
        let currentStyleKey = "sk-" + "ws-current-style-example-123456789"
        let authorizationLabel = "Author" + "ization"
        let apiKeyLabel = "api" + "_key"
        let input = "\(authorizationLabel): Bearer token-value \(apiKeyLabel)=another-value json={\"\(apiKeyLabel)\":\"third-value\"} key=\(currentStyleKey) exact=\(secret)"
        let output = SecretRedactor.redact(input, knownSecrets: [secret])
        XCTAssertFalse(output.contains(secret))
        XCTAssertFalse(output.contains("token-value"))
        XCTAssertFalse(output.contains("another-value"))
        XCTAssertFalse(output.contains("third-value"))
        XCTAssertFalse(output.contains(currentStyleKey))
        XCTAssertFalse(output.contains("sk-" + "ws-current"))
    }

    func testProviderPreferenceContainsNoSecretAndRestores() {
        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.preferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = ProviderPreferenceStore(defaults: defaults)
        first.selectedProvider = .deepSeek
        first.selectedStyle = .formalCommentary
        let second = ProviderPreferenceStore(defaults: defaults)
        XCTAssertEqual(second.selectedProvider, .deepSeek)
        XCTAssertEqual(second.selectedStyle, .formalCommentary)
        let persisted = defaults.persistentDomain(forName: suite) ?? [:]
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(persisted["selectedProvider"] as? String, "DeepSeek")
        XCTAssertEqual(persisted["selectedTranslationStyle"] as? String, "formal_commentary")
    }

    func testRuntimeCredentialDoesNotLeakIntoDefaultsOrAppOwnedFiles() throws {
        let secret = "FAKE_LEAK_SCAN_\(UUID().uuidString)"
        let store = SessionCredentialStore()
        try store.saveSecret(secret, for: .qwen, persistence: .sessionOnly)

        let suite = "com.example.EPUBTranslatorAppStore.Dev.tests.leak.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistedDescription = String(describing: defaults.persistentDomain(forName: suite) ?? [:])
        XCTAssertFalse(persistedDescription.contains(secret))

        let needle = Data(secret.utf8)
        let paths = try AppPaths.live()
        for root in [paths.applicationSupport, paths.caches, paths.temporary] {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, (values?.fileSize ?? 0) <= 5_000_000,
                      let data = try? Data(contentsOf: fileURL) else { continue }
                XCTAssertNil(data.range(of: needle), "API Key must not appear in App-owned files")
            }
        }
    }

    func testAppIdentityIsIsolatedFromPrivateEdition() {
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.example.EPUBTranslatorAppStore.Dev")
        XCTAssertTrue(AppIdentity.preferencesSuite.contains("AppStore"))
        XCTAssertEqual(AppIdentity.stateDirectoryName, "EPUBTranslatorAppStoreDev")
    }

    func testContainerPathsUseDedicatedNamespace() throws {
        let paths = try AppPaths.live()
        XCTAssertEqual(paths.applicationSupport.lastPathComponent, AppIdentity.stateDirectoryName)
        XCTAssertEqual(paths.caches.lastPathComponent, AppIdentity.stateDirectoryName)
        XCTAssertEqual(paths.temporary.lastPathComponent, AppIdentity.stateDirectoryName)
        XCTAssertFalse(paths.applicationSupport.path.contains("LegacyTranslator"))
    }
}

final class HelperClientTests: XCTestCase {
    private func helperURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(AppIdentity.helperName)
    }

    func testPingSuccessAndCleanExit() async throws {
        let response = try await HelperClient(executableURL: helperURL()).ping(timeout: 2)
        XCTAssertEqual(response, HelperResponse(ok: true, value: "pong", error: nil))
    }

    func testTimeoutTerminatesHelper() async throws {
        do {
            _ = try await HelperClient(executableURL: helperURL()).ping(timeout: 0.05, delayMilliseconds: 500)
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? HelperClientError, .timeout)
        }
    }

    func testHelperNotAvailable() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("self-authored-missing-helper-(UUID().uuidString)")
        do {
            _ = try await HelperClient(executableURL: missing).ping(timeout: 0.05)
            XCTFail("Expected notAvailable")
        } catch {
            XCTAssertEqual(error as? HelperClientError, .notAvailable)
        }
    }

    func testHelperExitedIsMapped() {
        do {
            _ = try HelperClient(executableURL: helperURL()).exitProbeSynchronously(timeout: 2)
            XCTFail("Expected exited")
        } catch {
            XCTAssertEqual(error as? HelperClientError, .exited(23))
        }
    }
}

final class UserFacingErrorTests: XCTestCase {
    private let context = UserFacingErrorContext(
        provider: .deepSeek,
        stage: "translation",
        completedUnits: 386,
        totalUnits: 524,
        retryCount: 1,
        style: .fluent
    )

    func testRequiredErrorMatrixUsesStableHumanReadableMappings() {
        let cases: [(Error, String)] = [
            (ProviderError(provider: .deepSeek, code: .invalidKey, httpStatus: 401), "PROVIDER_INVALID_CREDENTIAL"),
            (ProviderError(provider: .deepSeek, code: .quotaError, httpStatus: 402), "PROVIDER_QUOTA"),
            (ProviderError(provider: .deepSeek, code: .rateLimit, httpStatus: 429), "PROVIDER_RATE_LIMITED"),
            (ProviderError(provider: .deepSeek, code: .networkError), "PROVIDER_NETWORK"),
            (ProviderError(provider: .deepSeek, code: .timeout), "PROVIDER_TIMEOUT"),
            (ProviderError(provider: .deepSeek, code: .serverError, httpStatus: 503), "PROVIDER_SERVER"),
            (ProviderError(provider: .deepSeek, code: .emptyResponse), "PROVIDER_EMPTY_RESPONSE"),
            (ProviderError(provider: .deepSeek, code: .malformedResponse), "PROVIDER_MALFORMED_RESPONSE"),
            (ProviderError(provider: .qwen, code: .outputTruncated), "PROVIDER_OUTPUT_TRUNCATED"),
            (CredentialStoreError.invalidSecret, "PROVIDER_INVALID_CREDENTIAL_FORMAT"),
            (FileAccessError.invalidEPUB, "EPUB_INVALID"),
            (FileAccessError.unsupportedEncryptedContent, "EPUB_UNSUPPORTED_ENCRYPTION"),
            (FileAccessError.saveFailed, "OUTPUT_WRITE_FAILED"),
            (FileAccessError.diskSpaceLow, "DISK_SPACE_LOW"),
            (FileAccessError.checkpointRecoveryFailed, "CHECKPOINT_RECOVERY_FAILED"),
            (HelperClientError.notAvailable, "HELPER_UNAVAILABLE"),
            (HelperClientError.timeout, "HELPER_TIMEOUT"),
            (CancellationError(), "USER_CANCELLED"),
        ]

        for (source, expectedCode) in cases {
            let mapped = UserFacingErrorMapper.map(source, context: context)
            XCTAssertEqual(mapped.code, expectedCode)
            XCTAssertFalse(mapped.title.isEmpty)
            XCTAssertFalse(mapped.message.isEmpty)
            XCTAssertFalse(mapped.recoveryHint.isEmpty)
            XCTAssertFalse(mapped.title.contains("HTTP"))
            XCTAssertFalse(mapped.message.contains("NSURLError"))
        }

        let missing = UserFacingErrorMapper.missingAPI(.deepSeek, context: context)
        XCTAssertEqual(missing.code, "PROVIDER_MISSING_CREDENTIAL")
        XCTAssertEqual(missing.primaryAction, .openAPIManager)
    }

    func testRetryableProviderFailurePreservesExactProgress() {
        let mapped = UserFacingErrorMapper.map(
            ProviderError(provider: .deepSeek, code: .timeout),
            context: context
        )
        XCTAssertTrue(mapped.isRetryable)
        XCTAssertTrue(mapped.progressPreserved)
        XCTAssertEqual(mapped.primaryAction, .retryCurrent)
        XCTAssertEqual(mapped.context.completedUnits, 386)
        XCTAssertEqual(mapped.context.totalUnits, 524)
    }

    func testDiagnosticReportContainsOnlyAllowlistedContextAndRedactsSecretsAndPaths() {
        let unsafe = UserFacingError(
            code: "PROVIDER_TIMEOUT",
            category: .provider,
            severity: .notice,
            title: "超时",
            message: "安全消息",
            recoveryHint: "重试",
            primaryAction: .retryCurrent,
            secondaryAction: nil,
            isRetryable: true,
            progressPreserved: true,
            technicalDetails: [
                "sk-" + String(repeating: "B", count: 24),
                ["", "Users", "example-user", "Books", "PrivateBook.epub"]
                    .joined(separator: "/"),
            ].joined(separator: " "),
            context: context
        )
        let report = DiagnosticReportBuilder.make(
            error: unsafe,
            appVersion: "1.0.1",
            build: "4",
            osVersion: "macOS 15.6.1 (Build 24G90)",
            architecture: "arm64",
            timestamp: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.contains("EPUB翻译: 1.0.1"))
        XCTAssertTrue(report.contains("Provider: DeepSeek"))
        XCTAssertTrue(report.contains("Error Code: PROVIDER_TIMEOUT"))
        XCTAssertTrue(report.contains("Progress: 386/524"))
        XCTAssertFalse(report.contains(String(repeating: "B", count: 24)))
        XCTAssertFalse(report.contains(["", "Users", "example-user"].joined(separator: "/")))
        XCTAssertFalse(report.contains("PrivateBook"))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("authorization"))
    }

    func testGitHubFeedbackURLIsCentralizedAndDoesNotCarryUserData() throws {
        let components = try XCTUnwrap(URLComponents(url: SupportLinks.githubIssues, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/yyttwo/EPUB-Translator/issues/new")
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
    }

    func testEncryptionManifestAloneAndFontObfuscationAreNotClassifiedAsDRM() throws {
        try EPUBEncryptionInspector.validate(encryptionData: Data("<encryption/>".utf8), readingDocuments: ["EPUB/chapter.xhtml"])
        let fontOnly = """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData><EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
          <CipherData><CipherReference URI="EPUB/fonts/book.woff"/></CipherData></EncryptedData>
        </encryption>
        """
        try EPUBEncryptionInspector.validate(encryptionData: Data(fontOnly.utf8), readingDocuments: ["EPUB/chapter.xhtml"])
    }

    func testEncryptedReadingDocumentIsClassifiedAsUnsupportedContent() {
        let encryptedChapter = """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData><EncryptionMethod Algorithm="urn:example:content-encryption"/>
          <CipherData><CipherReference URI="EPUB/chapter.xhtml"/></CipherData></EncryptedData>
        </encryption>
        """
        XCTAssertThrowsError(try EPUBEncryptionInspector.validate(
            encryptionData: Data(encryptedChapter.utf8),
            readingDocuments: ["EPUB/chapter.xhtml"]
        )) { error in
            XCTAssertEqual(error as? FileAccessError, .unsupportedEncryptedContent)
        }
    }
}

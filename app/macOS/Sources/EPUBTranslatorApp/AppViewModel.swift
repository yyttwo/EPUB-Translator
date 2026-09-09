import AppKit
import Foundation
import UniformTypeIdentifiers

enum CredentialUIState: String {
    case notConfigured
    case validating
    case configured
    case failed

    var label: String {
        switch self {
        case .notConfigured: return "未配置"
        case .validating: return "验证中"
        case .configured: return "已配置"
        case .failed: return "验证失败"
        }
    }
}

enum TranslationRunState {
    case idle
    case running
    case completed
    case stopped
    case failed
}

@MainActor
protocol TranslatedEPUBSavePanelPresenting {
    func destinationURL(defaultFileName: String, initialDirectory: URL?) -> URL?
}

struct SystemTranslatedEPUBSavePanel: TranslatedEPUBSavePanelPresenting {
    func destinationURL(defaultFileName: String, initialDirectory: URL?) -> URL? {
        let panel = NSSavePanel()
        panel.title = "保存中文版 EPUB"
        panel.prompt = "保存译本"
        panel.nameFieldStringValue = defaultFileName
        panel.directoryURL = initialDirectory
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

#if DEBUG
struct Stage2MockTranslatedEPUBSavePanel: TranslatedEPUBSavePanelPresenting {
    func destinationURL(defaultFileName: String, initialDirectory: URL?) -> URL? {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ui-test-\(UUID().uuidString)-\(defaultFileName)")
    }
}
#endif

@MainActor
final class AppViewModel: ObservableObject {
    @Published var selectedProvider: ProviderID {
        didSet { preferences.selectedProvider = selectedProvider }
    }
    @Published var selectedStyle: TranslationStyle {
        didSet { preferences.selectedStyle = selectedStyle }
    }
    @Published var apiEntryProvider: ProviderID
    @Published var apiKeyInput = ""
    @Published private(set) var credentialStates: [ProviderID: CredentialUIState] = [:]
    @Published private(set) var credentialPersistences: [ProviderID: CredentialPersistence] = [:]
    @Published private(set) var selectedFileInfo: EPUBFileInfo?
    @Published private(set) var statusMessage = "请选择一本 DRM-free EPUB。"
    @Published private(set) var apiManagerMessage = "粘贴 API Key 后，App 会先验证；验证通过后仅在本次运行中使用。"
    @Published private(set) var providerBusy = false
    @Published private(set) var validatingProvider: ProviderID?
    @Published private(set) var isAnalyzingBook = false
    @Published private(set) var isTranslating = false
    @Published private(set) var completedTranslationUnits = 0
    @Published private(set) var translatedUnitResults: [String] = []
    @Published private(set) var translationRunState = TranslationRunState.idle
    @Published private(set) var preparedTranslatedEPUBURL: URL?
    @Published private(set) var savedTranslatedEPUBURL: URL?
    @Published private(set) var isSavingOutput = false
    @Published private(set) var activeError: UserFacingError?

    private(set) var selectedEPUBURL: URL?
    private let files: EPUBFileAccessService
    private let credentials: any CredentialStoring
    private let preferences: ProviderPreferenceStore
    private let providerTransport: ProviderHTTPTransport
    private let savePanel: any TranslatedEPUBSavePanelPresenting
    private let checkpointStore: any TranslationCheckpointStoring
    private var translationTask: Task<Void, Never>?
    private var credentialValidationTask: Task<Void, Never>?
    private var currentProviderRetryCount = 0
    private var selectedSourceFingerprint: String?
    private var translationCheckpoint: TranslationCheckpointRecord?

    var configuredProviders: [ProviderID] {
        ProviderID.allCases.filter(isCredentialConfigured)
    }

    var totalTranslationUnits: Int {
        selectedFileInfo?.translationUnitCount ?? 0
    }

    var translationProgress: Double {
        guard totalTranslationUnits > 0 else { return 0 }
        return min(1, max(0, Double(completedTranslationUnits) / Double(totalTranslationUnits)))
    }

    var translationPercentage: Int {
        Int((translationProgress * 100).rounded(.down))
    }

    var estimatedTranslationTime: String {
        guard let info = selectedFileInfo else { return "等待选择书籍" }
        let seconds = TranslationTimeEstimator.estimatedSeconds(for: info, provider: selectedProvider)
        return TranslationTimeEstimator.displayText(seconds: seconds)
    }

    var translatedTextPreview: String? {
        translatedUnitResults.last
    }

    var canResumeTranslation: Bool {
        let interrupted: Bool
        switch translationRunState {
        case .failed, .stopped: interrupted = true
        default: interrupted = false
        }
        guard interrupted,
              let checkpoint = translationCheckpoint,
              let sourceFingerprint = selectedSourceFingerprint,
              checkpoint.sourceFingerprint == sourceFingerprint,
              checkpoint.expectedUnitCount == totalTranslationUnits,
              checkpoint.provider == selectedProvider,
              checkpoint.style == selectedStyle,
              checkpoint.translations == translatedUnitResults,
              completedTranslationUnits == translatedUnitResults.count,
              completedTranslationUnits < totalTranslationUnits else {
            return false
        }
        return true
    }

    var progressTitle: String {
        if isAnalyzingBook { return "正在识别正文单元…" }
        guard totalTranslationUnits > 0 else { return "选择 EPUB 后显示进度" }
        switch translationRunState {
        case .running: return "正在翻译"
        case .completed: return "翻译完成"
        case .stopped: return "翻译已停止"
        case .failed: return "翻译已暂停"
        case .idle: return "已识别，等待开始"
        }
    }

    init(
        files: EPUBFileAccessService = EPUBFileAccessService(),
        credentials: (any CredentialStoring)? = nil,
        preferences: ProviderPreferenceStore = ProviderPreferenceStore(),
        providerTransport: ProviderHTTPTransport? = nil,
        savePanel: (any TranslatedEPUBSavePanelPresenting)? = nil,
        checkpointStore: (any TranslationCheckpointStoring)? = nil
    ) {
        self.files = files
        self.preferences = preferences
        #if DEBUG
        let usesUIMock = providerTransport == nil
            && CommandLine.arguments.contains("--stage2-ui-mock")
        self.credentials = credentials ?? SessionCredentialStore()
        self.providerTransport = usesUIMock
            ? Stage2UITestTransport()
            : (providerTransport ?? URLSessionProviderTransport())
        self.savePanel = savePanel ?? (usesUIMock
            ? Stage2MockTranslatedEPUBSavePanel()
            : SystemTranslatedEPUBSavePanel())
        self.checkpointStore = checkpointStore ?? ((usesUIMock || providerTransport != nil)
            ? MemoryTranslationCheckpointStore()
            : FileTranslationCheckpointStore())
        #else
        self.credentials = credentials ?? SessionCredentialStore()
        self.providerTransport = providerTransport ?? URLSessionProviderTransport()
        self.savePanel = savePanel ?? SystemTranslatedEPUBSavePanel()
        self.checkpointStore = checkpointStore ?? FileTranslationCheckpointStore()
        #endif
        self.selectedProvider = preferences.selectedProvider
        self.apiEntryProvider = preferences.selectedProvider
        self.selectedStyle = preferences.selectedStyle
        do {
            let paths = try AppPaths.live()
            try paths.createRequiredDirectories()
        } catch {
            presentError(error, stage: "startup")
        }
        refreshCredentialStates()
        #if DEBUG
        if let fixturePath = ProcessInfo.processInfo.environment["EPUB_TRANSLATOR_UI_FIXTURE"] {
            inspectEPUB(at: URL(fileURLWithPath: fixturePath))
        }
        injectUITestErrorIfRequested()
        #endif
    }

    func credentialState(for provider: ProviderID) -> CredentialUIState {
        credentialStates[provider] ?? .notConfigured
    }

    func isCredentialConfigured(for provider: ProviderID) -> Bool {
        credentialState(for: provider) == .configured
    }

    func hasStoredCredential(for provider: ProviderID) -> Bool {
        credentialPersistences[provider] != nil
    }

    func isProviderReady(for provider: ProviderID) -> Bool {
        credentialState(for: provider) == .configured
    }

    func credentialPersistence(for provider: ProviderID) -> CredentialPersistence? {
        credentialPersistences[provider]
    }

    func chooseEPUB() {
        guard !isTranslating else {
            statusMessage = "请先停止当前翻译，再选择其他 EPUB。"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "选择 DRM-free EPUB"
        panel.prompt = "选择 EPUB"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "epub") ?? .data]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        inspectEPUB(at: url)
    }

    func inspectEPUB(at url: URL) {
        guard !isTranslating else {
            statusMessage = "请先停止当前翻译，再选择其他 EPUB。"
            return
        }
        isAnalyzingBook = true
        clearPreparedOutput()
        selectedEPUBURL = nil
        selectedSourceFingerprint = nil
        selectedFileInfo = nil
        completedTranslationUnits = 0
        translatedUnitResults = []
        translationCheckpoint = nil
        translationRunState = .idle
        statusMessage = "正在读取 EPUB 目录、章节和正文单元…"
        activeError = nil
        defer { isAnalyzingBook = false }
        do {
            let plan = try files.loadTranslationPlan(at: url)
            let info = plan.info
            let fingerprint = TranslationSourceFingerprint.make(plan: plan)
            selectedEPUBURL = url
            selectedSourceFingerprint = fingerprint
            selectedFileInfo = info
            do {
                try restoreCheckpointIfAvailable(fingerprint: fingerprint, info: info)
            } catch {
                presentError(error, stage: "checkpoint_restore")
            }
        } catch {
            presentError(error, stage: "epub_read")
        }
    }

    func startTranslation() {
        guard !isTranslating else { return }
        guard let info = selectedFileInfo, let sourceURL = selectedEPUBURL else {
            let error = FileAccessError.invalidEPUB
            presentError(error, stage: "epub_selection")
            return
        }
        guard isCredentialConfigured(for: selectedProvider) else {
            activeError = UserFacingErrorMapper.missingAPI(selectedProvider, context: errorContext(stage: "credential"))
            statusMessage = activeError?.title ?? "还没有配置 AI 服务"
            return
        }

        let credential: String
        do {
            guard let saved = try credentials.readSecret(for: selectedProvider) else {
                credentialStates[selectedProvider] = .notConfigured
                activeError = UserFacingErrorMapper.missingAPI(selectedProvider, context: errorContext(stage: "credential"))
                statusMessage = activeError?.title ?? "还没有配置 AI 服务"
                return
            }
            credential = saved
        } catch {
            presentError(error, stage: "credential_read")
            return
        }

        let provider = selectedProvider
        let style = selectedStyle
        let shouldResume = canResumeTranslation
        if !shouldResume {
            guard let fingerprint = selectedSourceFingerprint else {
                presentError(FileAccessError.checkpointRecoveryFailed, stage: "checkpoint_prepare")
                return
            }
            do {
                clearPreparedOutput()
                completedTranslationUnits = 0
                translatedUnitResults = []
                let checkpoint = TranslationCheckpointRecord(
                    sourceFingerprint: fingerprint,
                    expectedUnitCount: info.translationUnitCount,
                    provider: provider,
                    style: style,
                    translations: []
                )
                try checkpointStore.save(checkpoint)
                translationCheckpoint = checkpoint
            } catch {
                presentError(error, stage: "checkpoint_prepare")
                return
            }
        }
        translationRunState = .running
        isTranslating = true
        currentProviderRetryCount = 0
        activeError = nil
        statusMessage = shouldResume
            ? "正在从第 \(completedTranslationUnits + 1) 个单元继续翻译…"
            : "正在准备 \(info.translationUnitCount) 个翻译单元…"
        translationTask = Task { [weak self] in
            guard let self else { return }
            await self.performTranslation(
                sourceURL: sourceURL,
                expectedUnitCount: info.translationUnitCount,
                bookTitle: info.bookTitle,
                provider: provider,
                style: style,
                credential: credential
            )
        }
    }

    func cancelTranslation() {
        guard isTranslating else { return }
        statusMessage = "正在停止翻译…"
        translationTask?.cancel()
    }

    private func performTranslation(
        sourceURL: URL,
        expectedUnitCount: Int,
        bookTitle: String?,
        provider: ProviderID,
        style: TranslationStyle,
        credential: String
    ) async {
        defer {
            isTranslating = false
            translationTask = nil
        }

        do {
            await Task.yield()
            let plan = try files.loadTranslationPlan(at: sourceURL)
            let units = plan.units
            let sourceFingerprint = TranslationSourceFingerprint.make(plan: plan)
            guard units.count == expectedUnitCount else { throw FileAccessError.invalidEPUB }
            guard translatedUnitResults.count == completedTranslationUnits,
                  translatedUnitResults.count <= units.count else {
                throw FileAccessError.translationMismatch
            }
            let adapter = try ProviderFactory.make(provider, transport: providerTransport)

            for index in translatedUnitResults.count..<units.count {
                try Task.checkCancellation()
                currentProviderRetryCount = 0
                statusMessage = "正在使用 \(provider.rawValue) 翻译第 \(index + 1) / \(units.count) 个单元…"
                let previousTranslation = translatedUnitResults.last
                let request = TranslationRequest(
                    sourceText: units[index].sourceText,
                    targetLanguage: "Simplified Chinese",
                    style: style,
                    context: TranslationContext(
                        chapterTitle: bookTitle,
                        previousSourceText: index > 0 ? units[index - 1].sourceText : nil,
                        previousTranslation: previousTranslation,
                        nextSourceText: index + 1 < units.count ? units[index + 1].sourceText : nil
                    ),
                    optionalGlossary: nil
                )
                let result = try await adapter.translate(
                    request,
                    credential: credential,
                    onRetry: { [weak self] reason, nextAttempt, maximumAttempts in
                        await MainActor.run {
                            self?.currentProviderRetryCount = max(0, nextAttempt - 1)
                            self?.statusMessage = "第 \(index + 1) / \(units.count) 个单元\(Self.retryReasonText(reason))，正在自动重试（第 \(nextAttempt) / \(maximumAttempts) 次）…"
                        }
                    }
                )
                try Task.checkCancellation()
                let updatedTranslations = translatedUnitResults + [result.text]
                try persistTranslationCheckpoint(
                    fingerprint: sourceFingerprint,
                    expectedUnitCount: units.count,
                    provider: provider,
                    style: style,
                    translations: updatedTranslations
                )
                translatedUnitResults = updatedTranslations
                completedTranslationUnits = index + 1
            }

            statusMessage = "正文翻译完成，正在生成中文版 EPUB…"
            let outputData = try files.buildTranslatedEPUB(
                at: sourceURL,
                plan: plan,
                translations: translatedUnitResults
            )
            preparedTranslatedEPUBURL = try writePreparedOutput(
                outputData,
                sourceFileName: plan.info.fileName
            )
            translationRunState = .completed
            translationCheckpoint = nil
            do {
                try checkpointStore.clear()
            } catch {
                presentError(error, stage: "checkpoint_cleanup")
            }
            statusMessage = "已完成 \(units.count) 个正文单元，中文版 EPUB 已生成。"
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.saveTranslatedEPUB()
            }
        } catch is CancellationError {
            translationRunState = .stopped
            activeError = nil
            statusMessage = "翻译已停止，已完成 \(completedTranslationUnits) / \(expectedUnitCount) 个单元。"
        } catch {
            translationRunState = .failed
            if let providerError = error as? ProviderError, providerError.code == .invalidKey {
                credentialStates[provider] = .failed
            }
            presentError(error, stage: "translation", retryCount: currentProviderRetryCount)
        }
    }

    func saveTranslatedEPUB() {
        guard !isSavingOutput,
              let preparedURL = preparedTranslatedEPUBURL,
              let originalURL = selectedEPUBURL else { return }
        let defaultName = Self.defaultOutputFileName(for: originalURL.lastPathComponent)
        guard let destination = savePanel.destinationURL(
            defaultFileName: defaultName,
            initialDirectory: originalURL.deletingLastPathComponent()
        ) else {
            statusMessage = "已完成 \(completedTranslationUnits) 个正文单元，中文版 EPUB 已生成；点击“保存译本…”可随时保存。"
            return
        }

        isSavingOutput = true
        defer { isSavingOutput = false }
        do {
            _ = try files.saveTranslatedEPUB(
                from: preparedURL,
                originalSource: originalURL,
                to: destination
            )
            savedTranslatedEPUBURL = destination
            activeError = nil
            statusMessage = "已完成 \(completedTranslationUnits) 个正文单元，中文版 EPUB 已保存。"
        } catch {
            presentError(error, stage: "output_save")
        }
    }

    func revealSavedTranslatedEPUB() {
        guard let url = savedTranslatedEPUBURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func writePreparedOutput(_ data: Data, sourceFileName: String) throws -> URL {
        let paths = try AppPaths.live()
        try paths.createRequiredDirectories()
        let baseName = URL(fileURLWithPath: sourceFileName).deletingPathExtension().lastPathComponent
        let safeBaseName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = paths.temporary.appendingPathComponent(
            "\(safeBaseName)-中文-\(UUID().uuidString).epub"
        )
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func restoreCheckpointIfAvailable(
        fingerprint: String,
        info: EPUBFileInfo
    ) throws {
        guard let checkpoint = try checkpointStore.load(),
              checkpoint.sourceFingerprint == fingerprint,
              checkpoint.expectedUnitCount == info.translationUnitCount,
              !checkpoint.translations.isEmpty else {
            statusMessage = "已识别 \(info.readingDocumentCount) 个正文文件、\(info.translationUnitCount) 个翻译单元。"
            return
        }
        translationCheckpoint = checkpoint
        translatedUnitResults = checkpoint.translations
        completedTranslationUnits = checkpoint.translations.count
        selectedProvider = checkpoint.provider
        selectedStyle = checkpoint.style
        translationRunState = .stopped
        statusMessage = "已恢复本地进度：\(completedTranslationUnits) / \(info.translationUnitCount) 个翻译单元。"
    }

    private func persistTranslationCheckpoint(
        fingerprint: String,
        expectedUnitCount: Int,
        provider: ProviderID,
        style: TranslationStyle,
        translations: [String]
    ) throws {
        let checkpoint = TranslationCheckpointRecord(
            sourceFingerprint: fingerprint,
            expectedUnitCount: expectedUnitCount,
            provider: provider,
            style: style,
            translations: translations
        )
        try checkpointStore.save(checkpoint)
        translationCheckpoint = checkpoint
    }

    private func clearPreparedOutput() {
        if let url = preparedTranslatedEPUBURL {
            try? FileManager.default.removeItem(at: url)
        }
        preparedTranslatedEPUBURL = nil
        savedTranslatedEPUBURL = nil
    }

    private static func defaultOutputFileName(for sourceFileName: String) -> String {
        let baseName = URL(fileURLWithPath: sourceFileName).deletingPathExtension().lastPathComponent
        let safeBaseName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(safeBaseName)-中文.epub"
    }

    func beginNewAPIEntry() {
        guard !providerBusy else { return }
        apiEntryProvider = selectedProvider
        apiKeyInput = ""
        apiManagerMessage = "请选择 Qwen 或 DeepSeek，然后粘贴该服务商的 API Key；密钥仅供本次运行使用。"
    }

    func beginCredentialEntry(for provider: ProviderID) {
        guard !providerBusy else { return }
        apiEntryProvider = provider
        apiKeyInput = ""
        apiManagerMessage = "正在更换 \(provider.rawValue) 的 API Key。新密钥验证成功前，本次运行中的原密钥会保持不变。"
    }

    func cancelCredentialEntry() {
        apiKeyInput = ""
        apiManagerMessage = "未更改已配置的 API。"
    }

    func saveEnteredAPI() {
        validateAndSaveEnteredAPI()
    }

    func validateAndSaveEnteredAPI() {
        guard !providerBusy else { return }
        let provider = apiEntryProvider
        let candidate = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            apiManagerMessage = "请输入 API 密钥。"
            activeError = UserFacingErrorMapper.missingAPI(
                provider,
                context: errorContext(stage: "credential_entry", provider: provider)
            )
            return
        }
        guard candidate.count >= 8 else {
            apiManagerMessage = "API Key 至少需要 8 个字符。"
            presentError(CredentialStoreError.invalidSecret, stage: "credential_entry", provider: provider)
            return
        }

        let previousWasConfigured = isCredentialConfigured(for: provider)
        let persistence: CredentialPersistence = .sessionOnly
        credentialStates[provider] = .validating
        providerBusy = true
        validatingProvider = provider
        apiManagerMessage = "正在连接 \(provider.rawValue) 并验证 API Key（最长约 15 秒，可随时取消）…"
        credentialValidationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishCredentialValidation() }
            do {
                let adapter = try ProviderFactory.make(provider, transport: self.providerTransport)
                _ = try await adapter.validateCredential(candidate)
                try self.credentials.saveSecret(candidate, for: provider, persistence: persistence)
                self.apiKeyInput = ""
                self.credentialStates[provider] = .configured
                self.credentialPersistences[provider] = persistence
                self.selectedProvider = provider
                self.activeError = nil
                self.apiManagerMessage = "\(provider.rawValue) 验证通过，API Key 仅保存在本次运行的内存中；关闭 App 后自动清除。"
            } catch is CancellationError {
                self.credentialStates[provider] = previousWasConfigured ? .configured : .notConfigured
                self.activeError = nil
                let preserved = previousWasConfigured ? "原有 API Key 已保留。" : "没有保存此 API Key。"
                self.apiManagerMessage = "已取消 \(provider.rawValue) 验证。\(preserved)"
            } catch {
                self.credentialStates[provider] = previousWasConfigured ? .configured : .failed
                let preserved = previousWasConfigured ? "原有 API Key 未被替换。" : "未保存此 API Key。"
                self.apiManagerMessage = "\(provider.rawValue) 验证未通过。\(preserved)"
                self.presentError(error, stage: "credential_validation", provider: provider)
            }
        }
    }

    private func refreshCredentialStates() {
        for provider in ProviderID.allCases {
            do {
                credentialStates[provider] = try credentials.hasSecret(for: provider)
                    ? .configured
                    : .notConfigured
                if credentialStates[provider] == .configured {
                    credentialPersistences[provider] = try credentials.persistence(for: provider)
                } else {
                    credentialPersistences[provider] = nil
                }
            } catch {
                credentialStates[provider] = .notConfigured
                credentialPersistences[provider] = nil
            }
        }
    }

    func validateCredential(for provider: ProviderID) {
        guard !providerBusy else { return }
        let credential: String
        do {
            guard let saved = try credentials.readSecret(for: provider) else {
                credentialStates[provider] = .notConfigured
                apiManagerMessage = "未找到 \(provider.rawValue) 的 API Key，请重新配置。"
                activeError = UserFacingErrorMapper.missingAPI(provider, context: errorContext(stage: "credential"))
                return
            }
            credential = saved
        } catch {
            credentialStates[provider] = .notConfigured
            apiManagerMessage = "无法读取本次运行中的 API Key，请重新输入并验证。"
            presentError(error, stage: "credential_read", provider: provider)
            return
        }

        credentialStates[provider] = .validating
        providerBusy = true
        validatingProvider = provider
        apiManagerMessage = "正在连接 \(provider.rawValue) 并重新验证（最长约 15 秒，可随时取消）…"
        credentialValidationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishCredentialValidation() }
            do {
                let adapter = try ProviderFactory.make(provider, transport: self.providerTransport)
                _ = try await adapter.validateCredential(credential)
                self.credentialStates[provider] = .configured
                self.selectedProvider = provider
                self.activeError = nil
                self.apiManagerMessage = "\(provider.rawValue) 验证通过，现在可以用于翻译。"
            } catch is CancellationError {
                self.credentialStates[provider] = .configured
                self.activeError = nil
                self.apiManagerMessage = "已取消 \(provider.rawValue) 验证，原有 API Key 已保留。"
            } catch {
                self.credentialStates[provider] = .configured
                self.apiManagerMessage = "\(provider.rawValue) 验证未通过，已保存的 API Key 没有被删除。"
                self.presentError(error, stage: "credential_validation", provider: provider)
            }
        }
    }

    func cancelCredentialValidation() {
        guard providerBusy, let provider = validatingProvider else { return }
        apiManagerMessage = "正在取消 \(provider.rawValue) 验证…"
        credentialValidationTask?.cancel()
    }

    private func finishCredentialValidation() {
        providerBusy = false
        validatingProvider = nil
        credentialValidationTask = nil
    }

    func deleteCredential(for provider: ProviderID) {
        guard !providerBusy else { return }
        do {
            try credentials.deleteSecret(for: provider)
            credentialStates[provider] = .notConfigured
            credentialPersistences[provider] = nil
            apiKeyInput = ""
            activeError = nil
            apiManagerMessage = "\(provider.rawValue) 的 API Key 已删除。"
        } catch {
            apiManagerMessage = "无法删除 API Key，请按提示重试。"
            presentError(error, stage: "credential_delete", provider: provider)
        }
    }

    func dismissActiveError() {
        activeError = nil
    }

    func performErrorAction(_ action: UserFacingErrorAction) {
        switch action {
        case .retryCurrent, .continueTranslation:
            activeError = nil
            retryCurrentWork()
        case .openAPIManager:
            activeError = nil
            NotificationCenter.default.post(name: .showAPIManagerPage, object: nil)
        case .chooseEPUB:
            activeError = nil
            chooseEPUB()
        case .chooseSaveLocation:
            activeError = nil
            saveTranslatedEPUB()
        case .reportProblem:
            SupportLinks.openIssues()
        case .dismiss:
            activeError = nil
        }
    }

    func copyActiveErrorDiagnostics() {
        guard let activeError else { return }
        let report = DiagnosticReportBuilder.make(error: activeError)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        statusMessage = "诊断信息已复制。粘贴反馈前请再次确认不含私人内容。"
    }

    func openFeedback() {
        SupportLinks.openIssues()
    }

    private func presentError(
        _ error: Error,
        stage: String,
        provider: ProviderID? = nil,
        retryCount: Int = 0
    ) {
        let context = errorContext(stage: stage, provider: provider, retryCount: retryCount)
        activeError = UserFacingErrorMapper.map(error, context: context)
        statusMessage = activeError?.title ?? "暂时无法完成操作"
    }

    private func errorContext(
        stage: String,
        provider: ProviderID? = nil,
        retryCount: Int = 0
    ) -> UserFacingErrorContext {
        UserFacingErrorContext(
            provider: provider ?? selectedProvider,
            stage: stage,
            completedUnits: completedTranslationUnits,
            totalUnits: totalTranslationUnits,
            retryCount: retryCount,
            style: selectedStyle
        )
    }

    private func retryCurrentWork() {
        if preparedTranslatedEPUBURL != nil {
            saveTranslatedEPUB()
        } else if totalTranslationUnits > 0,
                  completedTranslationUnits == totalTranslationUnits,
                  translatedUnitResults.count == totalTranslationUnits {
            rebuildCompletedTranslation()
        } else {
            startTranslation()
        }
    }

    private func rebuildCompletedTranslation() {
        guard !isTranslating,
              let sourceURL = selectedEPUBURL,
              let info = selectedFileInfo else { return }
        isTranslating = true
        translationRunState = .running
        statusMessage = "正在重新生成中文版 EPUB…"
        translationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isTranslating = false
                self.translationTask = nil
            }
            do {
                let plan = try self.files.loadTranslationPlan(at: sourceURL)
                guard plan.units.count == self.translatedUnitResults.count else {
                    throw FileAccessError.translationMismatch
                }
                let data = try self.files.buildTranslatedEPUB(
                    at: sourceURL, plan: plan, translations: self.translatedUnitResults
                )
                self.preparedTranslatedEPUBURL = try self.writePreparedOutput(
                    data, sourceFileName: info.fileName
                )
                self.translationRunState = .completed
                self.translationCheckpoint = nil
                self.statusMessage = "中文版 EPUB 已重新生成。"
                self.saveTranslatedEPUB()
            } catch {
                self.translationRunState = .failed
                self.presentError(error, stage: "epub_rebuild")
            }
        }
    }

    #if DEBUG
    private func injectUITestErrorIfRequested() {
        guard let value = ProcessInfo.processInfo.environment["EPUB_TRANSLATOR_UI_ERROR"] else { return }
        let error: Error
        switch value {
        case "invalid_key": error = ProviderError(provider: selectedProvider, code: .invalidKey, httpStatus: 401)
        case "network": error = ProviderError(provider: selectedProvider, code: .networkError)
        case "timeout": error = ProviderError(provider: selectedProvider, code: .timeout)
        case "output": error = FileAccessError.saveFailed
        case "encrypted": error = FileAccessError.unsupportedEncryptedContent
        default: return
        }
        translationRunState = .failed
        presentError(error, stage: value == "output" ? "output_save" : "translation", retryCount: 1)
    }
    #endif

    private static func retryReasonText(_ code: ProviderErrorCode) -> String {
        switch code {
        case .emptyResponse: return "返回了空内容"
        case .malformedResponse: return "返回格式不规范"
        case .outputTruncated: return "输出被截断"
        case .missingTargetText: return "没有生成中文译文"
        case .englishResidual: return "仍有较多英文未翻译"
        case .networkError: return "遇到网络中断"
        case .timeout: return "响应超时"
        case .serverError: return "遇到服务端异常"
        default: return "暂时无法完成"
        }
    }
}

import AppKit
import Foundation

enum UserFacingErrorCategory: String, Equatable { case provider, credential, epub, output, checkpoint, helper, system }
enum UserFacingErrorSeverity: String, Equatable { case notice, actionRequired, blocking }

enum UserFacingErrorAction: String, Equatable {
    case retryCurrent, continueTranslation, openAPIManager, chooseEPUB
    case chooseSaveLocation, reportProblem, dismiss

    var title: String {
        switch self {
        case .retryCurrent: return "重试当前内容"
        case .continueTranslation: return "继续翻译"
        case .openAPIManager: return "打开 API 管理"
        case .chooseEPUB: return "选择其他 EPUB"
        case .chooseSaveLocation: return "重新选择保存位置"
        case .reportProblem: return "反馈问题"
        case .dismiss: return "取消"
        }
    }
}

struct UserFacingErrorContext: Equatable {
    let provider: ProviderID?
    let stage: String
    let completedUnits: Int
    let totalUnits: Int
    let retryCount: Int
    let style: TranslationStyle?

    static let startup = Self(
        provider: nil, stage: "startup", completedUnits: 0,
        totalUnits: 0, retryCount: 0, style: nil
    )
}

struct UserFacingError: Identifiable, Equatable {
    let code: String
    let category: UserFacingErrorCategory
    let severity: UserFacingErrorSeverity
    let title: String
    let message: String
    let recoveryHint: String
    let primaryAction: UserFacingErrorAction
    let secondaryAction: UserFacingErrorAction?
    let isRetryable: Bool
    let progressPreserved: Bool
    let technicalDetails: String
    let context: UserFacingErrorContext
    var id: String { code }
}

enum UserFacingErrorMapper {
    static func map(_ error: Error, context: UserFacingErrorContext) -> UserFacingError {
        if error is CancellationError { return cancelled(context) }
        if let value = error as? ProviderError { return provider(value, context) }
        if let value = error as? FileAccessError { return file(value, context) }
        if let value = error as? CredentialStoreError { return credential(value, context) }
        if let value = error as? HelperClientError { return helper(value, context) }
        if isDiskFull(error) { return diskSpace(context) }
        return make(
            "UNKNOWN_OPERATION_FAILURE", .system, .blocking,
            "暂时无法完成操作", "发生了未预期的问题，已经完成的内容不会受到影响。",
            "请重新尝试。如果问题持续存在，可以向作者反馈。",
            .retryCurrent, .reportProblem, true, true, context, "unclassified_failure"
        )
    }

    static func missingAPI(_ provider: ProviderID, context: UserFacingErrorContext) -> UserFacingError {
        make(
            "PROVIDER_MISSING_CREDENTIAL", .credential, .actionRequired,
            "还没有配置 AI 服务", "请先在 API 管理中配置 \(provider.rawValue)。",
            "配置并验证 API Key 后即可继续翻译。",
            .openAPIManager, .dismiss, false, true, context, "credential_not_configured"
        )
    }

    private static func provider(_ error: ProviderError, _ context: UserFacingErrorContext) -> UserFacingError {
        let name = error.provider.rawValue
        let progress = progressHint(context)
        switch error.code {
        case .missingCredential:
            return missingAPI(error.provider, context: context)
        case .invalidKey:
            return make("PROVIDER_INVALID_CREDENTIAL", .credential, .actionRequired,
                "\(name) API Key 无效", "请检查当前 API Key，或重新配置一个新的 API Key。",
                progress, .openAPIManager, .dismiss, false, true, context, httpReason(error))
        case .quotaError:
            return make("PROVIDER_QUOTA", .provider, .actionRequired,
                "AI 服务额度可能不足", "请前往 \(name) 检查账户余额或使用额度。",
                progress, .openAPIManager, .dismiss, false, true, context, httpReason(error))
        case .rateLimit:
            return make("PROVIDER_RATE_LIMITED", .provider, .notice,
                "请求过于频繁", "AI 服务暂时限制了请求。",
                progress, .continueTranslation, .dismiss, true, true, context, httpReason(error))
        case .networkError:
            return make("PROVIDER_NETWORK", .provider, .notice,
                "网络连接中断", "翻译已暂停，已经完成的内容和进度都已保留。",
                "网络恢复后，从未完成的位置继续翻译。",
                .continueTranslation, .dismiss, true, true, context, "network_unavailable")
        case .timeout:
            return make("PROVIDER_TIMEOUT", .provider, .notice,
                "AI 服务响应超时", "当前文本块尚未完成，其他已经完成的内容不会受到影响。",
                "只会重新尝试当前未完成的内容。",
                .retryCurrent, .dismiss, true, true, context, "request_timeout")
        case .serverError:
            return make("PROVIDER_SERVER", .provider, .notice,
                "\(name) 暂时无法完成请求", "这通常是 AI 服务暂时异常。",
                progress, .retryCurrent, .reportProblem, true, true, context, httpReason(error))
        case .emptyResponse:
            return make("PROVIDER_EMPTY_RESPONSE", .provider, .notice,
                "AI 服务没有返回有效译文", "当前内容尚未完成，可以重新尝试。",
                progress, .retryCurrent, .dismiss, true, true, context, "empty_response")
        case .malformedResponse, .missingTargetText:
            return make("PROVIDER_MALFORMED_RESPONSE", .provider, .notice,
                "AI 服务返回了无法识别的结果", "当前内容没有写入电子书，可以重新尝试。",
                progress, .retryCurrent, .dismiss, true, true, context, error.code.rawValue.lowercased())
        case .outputTruncated:
            return make("PROVIDER_OUTPUT_TRUNCATED", .provider, .notice,
                "AI 服务的译文被截断", "App 已尝试缩小当前文本块，但仍未得到完整译文。",
                progress, .retryCurrent, .dismiss, true, true, context, "output_truncated")
        case .englishResidual:
            return make("PROVIDER_INCOMPLETE_TRANSLATION", .provider, .notice,
                "当前内容可能没有完整翻译", "为避免明显漏译，当前文本块尚未写入电子书。",
                progress, .retryCurrent, .reportProblem, true, true, context, "english_residual")
        case .providerRefusal, .unknownProviderError:
            return make("PROVIDER_REQUEST_FAILED", .provider, .notice,
                "\(name) 暂时无法完成请求", "AI 服务没有完成当前内容。",
                progress, .retryCurrent, .reportProblem, true, true, context, httpReason(error))
        }
    }

    private static func file(_ error: FileAccessError, _ context: UserFacingErrorContext) -> UserFacingError {
        switch error {
        case .unsupportedEncryptedContent:
            return make("EPUB_UNSUPPORTED_ENCRYPTION", .epub, .blocking,
                "此 EPUB 可能包含 DRM 或不受支持的加密内容",
                "EPUB翻译目前只能处理能够正常读取的 DRM-free EPUB。",
                "请选择能够正常读取的其他 EPUB。", .chooseEPUB, .dismiss,
                false, false, context, "encrypted_reading_content")
        case .fileMissing, .invalidEPUB, .unsupportedEPUBCompression, .permissionExpired, .readFailed:
            return make("EPUB_INVALID", .epub, .blocking,
                "无法读取这本 EPUB", "文件可能已损坏，或使用了当前版本不支持的 EPUB 结构。",
                "请选择其他 EPUB 后再试。", .chooseEPUB, .dismiss,
                false, false, context, fileReason(error))
        case .diskSpaceLow:
            return diskSpace(context)
        case .targetNotWritable, .saveFailed, .sourceOverwrite:
            return make("OUTPUT_WRITE_FAILED", .output, .actionRequired,
                "中文版 EPUB 保存失败", "原始 EPUB 和已完成的翻译不会受到影响。",
                "请选择另一个可写入的保存位置。", .chooseSaveLocation, .dismiss,
                true, true, context, fileReason(error))
        case .checkpointRecoveryFailed:
            return make("CHECKPOINT_RECOVERY_FAILED", .checkpoint, .blocking,
                "无法恢复上次翻译任务", "原始 EPUB 不会受到影响。",
                "查看详细信息后再决定是否重新开始；App 不会自动删除旧进度。",
                .dismiss, .reportProblem, false, true, context, "checkpoint_unreadable")
        case .uncoveredVisibleText, .translationMismatch, .rebuildFailed:
            return make("EPUB_REBUILD_FAILED", .output, .blocking,
                "暂时无法生成中文版 EPUB", "检测到电子书结构或正文完整性问题，未生成不完整文件。",
                "原始 EPUB 和已经完成的译文不会受到影响。",
                .retryCurrent, .reportProblem, true, true, context, fileReason(error))
        }
    }

    private static func credential(_ error: CredentialStoreError, _ context: UserFacingErrorContext) -> UserFacingError {
        switch error {
        case .invalidSecret:
            return make("PROVIDER_INVALID_CREDENTIAL_FORMAT", .credential, .actionRequired,
                "API Key 格式不完整", "请输入至少 8 个字符的 API Key。",
                "App 只会使用你在此处输入并验证通过的 API Key。",
                .openAPIManager, .dismiss, false, true, context, "credential_format_invalid")
        case .readFailed:
            return make("CREDENTIAL_READ_FAILED", .credential, .actionRequired,
                "无法读取本次 API Key", "请重新输入并验证该 AI 服务。",
                progressHint(context), .openAPIManager, .dismiss,
                false, true, context, "session_credential_unavailable")
        case .updateFailed, .deleteFailed:
            return make("CREDENTIAL_UPDATE_FAILED", .credential, .actionRequired,
                "无法更新 API Key", "本次运行中的 API Key 没有完成更新。",
                "原有 API Key 不会被意外替换，请重新输入后再试。",
                .openAPIManager, .dismiss, true, true, context, "session_credential_update_failed")
        }
    }

    private static func helper(_ error: HelperClientError, _ context: UserFacingErrorContext) -> UserFacingError {
        let code = error == .timeout ? "HELPER_TIMEOUT" : "HELPER_UNAVAILABLE"
        return make(code, .helper, .blocking,
            "翻译组件暂时无法使用",
            "请重新尝试。如果问题持续存在，可以通过 GitHub 向作者反馈。",
            progressHint(context), .retryCurrent, .reportProblem,
            true, true, context, code.lowercased())
    }

    private static func cancelled(_ context: UserFacingErrorContext) -> UserFacingError {
        make("USER_CANCELLED", .system, .notice,
            "翻译已暂停", "已经完成的内容和进度都已保留。",
            "准备好后可以从未完成的位置继续。",
            .continueTranslation, .dismiss, true, true, context, "user_cancelled")
    }

    private static func diskSpace(_ context: UserFacingErrorContext) -> UserFacingError {
        make("DISK_SPACE_LOW", .output, .actionRequired,
            "Mac 可用空间不足", "请释放一些存储空间后重新尝试。",
            "App 不会自动删除任何用户文件。",
            .retryCurrent, .dismiss, true, true, context, "no_space_left")
    }

    private static func make(
        _ code: String, _ category: UserFacingErrorCategory, _ severity: UserFacingErrorSeverity,
        _ title: String, _ message: String, _ hint: String,
        _ primary: UserFacingErrorAction, _ secondary: UserFacingErrorAction?,
        _ retryable: Bool, _ preserved: Bool, _ context: UserFacingErrorContext, _ reason: String
    ) -> UserFacingError {
        UserFacingError(
            code: code, category: category, severity: severity, title: title,
            message: message, recoveryHint: hint, primaryAction: primary,
            secondaryAction: secondary, isRetryable: retryable,
            progressPreserved: preserved, technicalDetails: "reason=\(reason)", context: context
        )
    }

    private static func progressHint(_ context: UserFacingErrorContext) -> String {
        guard context.totalUnits > 0 else { return "当前操作尚未完成，可以按提示继续。" }
        return "已完成 \(context.completedUnits) / \(context.totalUnits) 个文本块，进度已保留。"
    }

    private static func httpReason(_ error: ProviderError) -> String {
        error.httpStatus.map { "http_status_\($0)" } ?? error.code.rawValue.lowercased()
    }

    private static func fileReason(_ error: FileAccessError) -> String {
        String(describing: error).replacingOccurrences(of: " ", with: "_").lowercased()
    }

    private static func isDiskFull(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileWriteOutOfSpace { return true }
        let nsError = error as NSError
        return nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)
    }
}

enum SupportLinks {
    static let githubRepository = URL(string: "https://github.com/yyttwo/EPUB-Translator")!
    static let githubIssues = URL(string: "https://github.com/yyttwo/EPUB-Translator/issues/new")!
    static let privacy = githubRepository.appendingPathComponent("blob/main/PRIVACY.md")

    @MainActor static func openIssues() { NSWorkspace.shared.open(githubIssues) }
}

enum DiagnosticReportBuilder {
    static func make(
        error: UserFacingError,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
        build: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: String = currentArchitecture,
        timestamp: Date = Date()
    ) -> String {
        let context = error.context
        let lines = [
            "EPUB翻译: \(appVersion)", "Build: \(build)",
            "macOS: \(safeOSVersion(osVersion))", "Architecture: \(architecture)",
            "Provider: \(context.provider?.rawValue ?? "not_selected")",
            "Translation Style: \(context.style?.rawValue ?? "not_selected")",
            "Error Code: \(error.code)", "Stage: \(safeToken(context.stage))",
            "Progress: \(context.completedUnits)/\(context.totalUnits)",
            "Retry Count: \(context.retryCount)",
            "Technical Reason: \(safeToken(SecretRedactor.redact(error.technicalDetails)))",
            "Timestamp: \(ISO8601DateFormatter().string(from: timestamp))",
        ]
        return SecretRedactor.redact(lines.joined(separator: "\n"))
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func safeOSVersion(_ value: String) -> String {
        value.filter { $0.isNumber || $0 == "." || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }

    private static func safeToken(_ value: String) -> String {
        let pathRedacted = value.replacingOccurrences(
            of: #"(?:file://)?/(?:Users|home)/[^\s]+"#,
            with: "[REDACTED]",
            options: .regularExpression
        )
        return String(pathRedacted.prefix(160)).filter {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "=" || $0 == " "
        }
    }
}

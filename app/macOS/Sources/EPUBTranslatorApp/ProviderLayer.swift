import Foundation

struct TranslationContext: Codable, Equatable {
    let chapterTitle: String?
    let previousSourceText: String?
    let previousTranslation: String?
    let nextSourceText: String?

    static let empty = TranslationContext(
        chapterTitle: nil,
        previousSourceText: nil,
        previousTranslation: nil,
        nextSourceText: nil
    )
}

struct TranslationRequest: Equatable {
    let sourceText: String
    let targetLanguage: String
    let style: TranslationStyle
    let context: TranslationContext?
    let optionalGlossary: [String: String]?
}

struct ProviderMetadata: Equatable {
    let providerID: ProviderID
    let displayName: String
    let modelID: String
    let endpoint: URL
    let apiVersion: String
    let requestTimeout: TimeInterval
    let temperature: Double
    let maxTokens: Int

    static let qwen = ProviderMetadata(
        providerID: .qwen,
        displayName: "Qwen",
        modelID: "qwen3.7-plus",
        endpoint: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
        apiVersion: "OpenAI-compatible Chat Completions",
        requestTimeout: 45,
        temperature: 0.1,
        maxTokens: 4_096
    )

    static let deepSeek = ProviderMetadata(
        providerID: .deepSeek,
        displayName: "DeepSeek",
        modelID: "deepseek-v4-flash",
        endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
        apiVersion: "OpenAI-compatible Chat Completions",
        requestTimeout: 45,
        temperature: 0.1,
        maxTokens: 4_096
    )

    static func profile(for provider: ProviderID) -> ProviderMetadata {
        switch provider {
        case .qwen: return .qwen
        case .deepSeek: return .deepSeek
        }
    }
}

enum ProviderEndpointPolicy {
    static func validate(_ metadata: ProviderMetadata) throws {
        let endpoint = metadata.endpoint
        guard endpoint.scheme == "https",
              endpoint.user == nil,
              endpoint.password == nil,
              endpoint.query == nil,
              endpoint.fragment == nil,
              let host = endpoint.host?.lowercased() else {
            throw ProviderError(provider: metadata.providerID, code: .providerRefusal)
        }
        switch metadata.providerID {
        case .qwen:
            guard host == "dashscope.aliyuncs.com",
                  endpoint.path == "/compatible-mode/v1/chat/completions" else {
                throw ProviderError(provider: metadata.providerID, code: .providerRefusal)
            }
        case .deepSeek:
            guard host == "api.deepseek.com", endpoint.path == "/chat/completions" else {
                throw ProviderError(provider: metadata.providerID, code: .providerRefusal)
            }
        }
    }
}

enum ProviderErrorCode: String, Codable, CaseIterable {
    case missingCredential = "MISSING_CREDENTIAL"
    case invalidKey = "INVALID_KEY"
    case networkError = "NETWORK_ERROR"
    case timeout = "TIMEOUT"
    case rateLimit = "RATE_LIMIT"
    case quotaError = "QUOTA_ERROR"
    case serverError = "SERVER_ERROR"
    case emptyResponse = "EMPTY_RESPONSE"
    case malformedResponse = "MALFORMED_RESPONSE"
    case outputTruncated = "OUTPUT_TRUNCATED"
    case missingTargetText = "MISSING_TARGET_TEXT"
    case englishResidual = "ENGLISH_RESIDUAL"
    case providerRefusal = "PROVIDER_REFUSAL"
    case unknownProviderError = "UNKNOWN_PROVIDER_ERROR"
}

struct ProviderError: LocalizedError, Equatable {
    let provider: ProviderID
    let code: ProviderErrorCode
    let httpStatus: Int?

    init(provider: ProviderID, code: ProviderErrorCode, httpStatus: Int? = nil) {
        self.provider = provider
        self.code = code
        self.httpStatus = httpStatus
    }

    var errorDescription: String? {
        switch code {
        case .missingCredential:
            return "请先到 API 管理配置所选 AI 服务。"
        case .invalidKey:
            return "API Key 无效，请检查后重新输入。"
        case .networkError:
            return "当前无法连接网络，请检查网络后重试。"
        case .timeout:
            return "AI 服务响应超时，请稍后重试。"
        case .rateLimit:
            return "AI 服务请求过于频繁，请稍后再试。"
        case .quotaError:
            return "当前 AI 账户额度可能不足，请前往服务商检查账户。"
        case .serverError:
            return "AI 服务暂时不可用，请稍后重试。"
        case .providerRefusal:
            return "AI 服务拒绝了本次请求，请检查账户状态。"
        case .emptyResponse:
            return "AI 服务连续返回空内容，翻译已暂停；可点击“继续翻译”重试当前单元。"
        case .malformedResponse:
            return "AI 服务连续返回无法识别的格式，翻译已暂停；可点击“继续翻译”重试当前单元。"
        case .outputTruncated:
            return "AI 服务的输出被截断，当前单元尚未完成。"
        case .missingTargetText:
            return "AI 服务连续未生成中文译文，翻译已暂停；可点击“继续翻译”重试当前单元。"
        case .englishResidual:
            return "AI 服务补译后仍有整句或大段英文，为避免生成明显漏译文件，翻译已暂停。"
        case .unknownProviderError:
            return "AI 服务请求失败，请稍后重试。"
        }
    }

    var retryable: Bool {
        switch code {
        case .networkError, .timeout, .serverError, .emptyResponse,
             .malformedResponse, .outputTruncated, .missingTargetText, .englishResidual:
            return true
        default:
            return false
        }
    }
}

struct ProviderDiagnostics: Equatable {
    let requestID: String?
    let provider: ProviderID
    let statusCode: Int
    let latencyMilliseconds: Int
    let inputCharacters: Int
    let responseBytes: Int
    let attempts: Int
}

struct TranslationResult: Equatable {
    let text: String
    let metadata: ProviderMetadata
    let diagnostics: ProviderDiagnostics
}

enum TranslationResidualSeverity: Equatable {
    case clean
    case tolerated
    case suspicious
    case severe
}

struct TranslationResidualAssessment: Equatable {
    let words: [String]
    let unexpectedLatinRatio: Double
    let severity: TranslationResidualSeverity
}

enum TranslationResidualDetector {
    static let toleratedMaximumWordCount = 2
    static let severeMinimumWordCount = 8

    private static let removablePatterns = [
        #"https?://[^\s]+"#,
        #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#,
        #"\b[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,8}\b"#,
        #"`[^`]*`"#,
    ]
    private static let ordinaryEnglishWord = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])[a-z][a-z'-]{1,}(?![A-Za-z])"#
    )

    static func unexpectedEnglishWords(in text: String) -> [String] {
        assessment(of: text).words
    }

    static func assessment(of text: String) -> TranslationResidualAssessment {
        var candidate = text
        for pattern in removablePatterns {
            candidate = candidate.replacingOccurrences(
                of: pattern,
                with: " ",
                options: .regularExpression
            )
        }
        let range = NSRange(candidate.startIndex..<candidate.endIndex, in: candidate)
        let words = ordinaryEnglishWord.matches(in: candidate, range: range).compactMap {
            Range($0.range, in: candidate).map { String(candidate[$0]) }
        }
        let unexpectedLatinCount = words.reduce(0) { $0 + $1.unicodeScalars.count }
        let letterCount = max(1, candidate.unicodeScalars.filter { $0.properties.isAlphabetic }.count)
        let ratio = Double(unexpectedLatinCount) / Double(letterCount)
        let severity: TranslationResidualSeverity
        if words.isEmpty {
            severity = .clean
        } else if words.count <= toleratedMaximumWordCount {
            severity = .tolerated
        } else if words.count >= severeMinimumWordCount
            || (words.count >= 5 && ratio >= 0.45) {
            severity = .severe
        } else {
            severity = .suspicious
        }
        return TranslationResidualAssessment(
            words: words,
            unexpectedLatinRatio: ratio,
            severity: severity
        )
    }
}

/// Technical-only blocks carry no natural-language content to translate. Keeping them locally
/// avoids asking a provider to "translate" a URL and then rejecting the correct unchanged value.
enum TranslationPassThroughPolicy {
    private static let wrapperCharacters = CharacterSet(
        charactersIn: "()[]{}<>\"'“”‘’，,;；!?！？"
    )

    static func shouldPreserve(_ rawText: String) -> Bool {
        let text = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return !tokens.isEmpty && tokens.allSatisfy(isTechnicalToken)
    }

    private static func isTechnicalToken(_ rawToken: String) -> Bool {
        let token = rawToken.trimmingCharacters(in: wrapperCharacters)
        guard !token.isEmpty else { return false }

        if let components = URLComponents(string: token),
           let scheme = components.scheme?.lowercased(),
           ["http", "https", "ftp"].contains(scheme),
           components.host?.isEmpty == false {
            return true
        }
        if token.lowercased().hasPrefix("www."),
           let components = URLComponents(string: "https://\(token)"),
           components.host?.contains(".") == true {
            return true
        }
        if matches(token, pattern: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, caseInsensitive: true) {
            return true
        }
        if matches(token, pattern: #"^[A-Za-z0-9][A-Za-z0-9._-]*\.[A-Za-z0-9]{1,10}$"#) {
            return true
        }
        if token.contains(where: { $0.isNumber }),
           matches(token, pattern: #"^[A-Za-z0-9#§+._:/%°-]+$"#) {
            return true
        }
        return false
    }

    private static func matches(
        _ value: String,
        pattern: String,
        caseInsensitive: Bool = false
    ) -> Bool {
        let options: String.CompareOptions = caseInsensitive
            ? [.regularExpression, .caseInsensitive]
            : [.regularExpression]
        return value.range(of: pattern, options: options) != nil
    }
}

protocol ProviderHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionProviderTransport: ProviderHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

enum ProviderPrompts {
    static let schemaVersion = "translation-request-v1"
    static let healthSource = "The reading room is quiet."
    static let translationFixture = "The company increased free cash flow, but management expects slower growth next year."
}

protocol TranslationProvider {
    var providerID: ProviderID { get }
    var displayName: String { get }
    func validateCredential(_ credential: String) async throws -> ProviderDiagnostics
    func translate(
        _ request: TranslationRequest,
        credential: String,
        onRetry: ProviderRetryHandler?
    ) async throws -> TranslationResult
}

typealias ProviderRetryHandler = (
    _ reason: ProviderErrorCode,
    _ nextAttempt: Int,
    _ maximumAttempts: Int
) async -> Void

enum ProviderRecoverySplitter {
    static let minimumCharacters = 160

    static func pieces(from rawText: String, maximumCharacters: Int = 600) -> [String] {
        let text = normalized(rawText)
        guard text.count > minimumCharacters else { return [text] }

        var sentences: [String] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.bySentences]
        ) { substring, _, _, _ in
            if let substring {
                let sentence = normalized(substring)
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
            let piece = normalized(String(remaining[..<cut]))
            if !piece.isEmpty { pieces.append(piece) }
            remaining = remaining[cut...].drop(while: { $0.isWhitespace })
        }
        let tail = normalized(String(remaining))
        if !tail.isEmpty { pieces.append(tail) }
        return pieces
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

extension TranslationProvider {
    func translate(_ request: TranslationRequest, credential: String) async throws -> TranslationResult {
        try await translate(request, credential: credential, onRetry: nil)
    }
}

private final class OpenAICompatibleProvider {
    private static let credentialValidationTimeout: TimeInterval = 15

    let metadata: ProviderMetadata
    private let transport: ProviderHTTPTransport
    private let retryMax: Int

    init(
        metadata: ProviderMetadata,
        transport: ProviderHTTPTransport,
        retryMax: Int = 1
    ) throws {
        try ProviderEndpointPolicy.validate(metadata)
        self.metadata = metadata
        self.transport = transport
        self.retryMax = retryMax
    }

    func validateCredential(_ credential: String) async throws -> ProviderDiagnostics {
        let cleanCredential = try validatedCredential(credential)
        let result = try await translateWithRetries(
            TranslationRequest(
                sourceText: ProviderPrompts.healthSource,
                targetLanguage: "Simplified Chinese",
                style: .literal,
                context: nil,
                optionalGlossary: nil
            ),
            credential: cleanCredential,
            onRetry: nil,
            retryLimitOverride: 0,
            requestTimeoutOverride: Self.credentialValidationTimeout
        )
        return result.diagnostics
    }

    func translate(
        _ request: TranslationRequest,
        credential: String,
        onRetry: ProviderRetryHandler? = nil
    ) async throws -> TranslationResult {
        let cleanCredential = try validatedCredential(credential)
        guard !request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError(provider: metadata.providerID, code: .missingTargetText)
        }

        if TranslationPassThroughPolicy.shouldPreserve(request.sourceText) {
            return TranslationResult(
                text: request.sourceText,
                metadata: metadata,
                diagnostics: ProviderDiagnostics(
                    requestID: nil,
                    provider: metadata.providerID,
                    statusCode: 0,
                    latencyMilliseconds: 0,
                    inputCharacters: request.sourceText.count,
                    responseBytes: 0,
                    attempts: 0
                )
            )
        }

        return try await translateRecovering(
            request,
            credential: cleanCredential,
            onRetry: onRetry,
            recoveryDepth: 0
        )
    }

    private func translateRecovering(
        _ request: TranslationRequest,
        credential: String,
        onRetry: ProviderRetryHandler?,
        recoveryDepth: Int
    ) async throws -> TranslationResult {
        do {
            return try await translateWithRetries(
                request,
                credential: credential,
                onRetry: onRetry
            )
        } catch let failure as ProviderError {
            guard shouldSubdivide(failure.code, request: request, recoveryDepth: recoveryDepth) else {
                throw failure
            }
            let targetCharacters = recoveryDepth == 0 ? 600 : 300
            let pieces = ProviderRecoverySplitter.pieces(
                from: request.sourceText,
                maximumCharacters: targetCharacters
            )
            guard pieces.count > 1 else { throw failure }

            var translatedPieces: [String] = []
            var diagnostics: [ProviderDiagnostics] = []
            for (index, piece) in pieces.enumerated() {
                try Task.checkCancellation()
                let parentContext = request.context ?? .empty
                let pieceRequest = TranslationRequest(
                    sourceText: piece,
                    targetLanguage: request.targetLanguage,
                    style: request.style,
                    context: TranslationContext(
                        chapterTitle: parentContext.chapterTitle,
                        previousSourceText: index > 0 ? pieces[index - 1] : parentContext.previousSourceText,
                        previousTranslation: translatedPieces.last ?? parentContext.previousTranslation,
                        nextSourceText: index + 1 < pieces.count ? pieces[index + 1] : parentContext.nextSourceText
                    ),
                    optionalGlossary: request.optionalGlossary
                )
                let result = try await translateRecovering(
                    pieceRequest,
                    credential: credential,
                    onRetry: onRetry,
                    recoveryDepth: recoveryDepth + 1
                )
                translatedPieces.append(result.text)
                diagnostics.append(result.diagnostics)
            }
            guard let last = diagnostics.last else { throw failure }
            return TranslationResult(
                text: translatedPieces.joined(),
                metadata: metadata,
                diagnostics: ProviderDiagnostics(
                    requestID: last.requestID,
                    provider: metadata.providerID,
                    statusCode: last.statusCode,
                    latencyMilliseconds: diagnostics.reduce(0) { $0 + $1.latencyMilliseconds },
                    inputCharacters: request.sourceText.count,
                    responseBytes: diagnostics.reduce(0) { $0 + $1.responseBytes },
                    attempts: diagnostics.reduce(0) { $0 + $1.attempts }
                )
            )
        }
    }

    private func translateWithRetries(
        _ request: TranslationRequest,
        credential: String,
        onRetry: ProviderRetryHandler?,
        retryLimitOverride: Int? = nil,
        requestTimeoutOverride: TimeInterval? = nil
    ) async throws -> TranslationResult {

        var attempt = 0
        var correctionReason: ProviderErrorCode?
        while true {
            attempt += 1
            do {
                return try await translateOnce(
                    request,
                    credential: credential,
                    attempt: attempt,
                    correctionReason: correctionReason,
                    requestTimeoutOverride: requestTimeoutOverride
                )
            } catch let failure as ProviderError {
                let maximumRetries = retryLimitOverride ?? retryLimit(for: failure.code)
                if isCorrectableOutput(failure.code) { correctionReason = failure.code }
                if failure.retryable && attempt <= maximumRetries {
                    await onRetry?(failure.code, attempt + 1, maximumRetries + 1)
                    continue
                }
                throw failure
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                let failure = classifyTransportFailure(error)
                let maximumRetries = retryLimitOverride ?? retryLimit(for: failure.code)
                if failure.retryable && attempt <= maximumRetries {
                    await onRetry?(failure.code, attempt + 1, maximumRetries + 1)
                    continue
                }
                throw failure
            }
        }
    }

    private func translateOnce(
        _ translationRequest: TranslationRequest,
        credential: String,
        attempt: Int,
        correctionReason: ProviderErrorCode?,
        requestTimeoutOverride: TimeInterval? = nil
    ) async throws -> TranslationResult {
        let profile = TranslationStylePromptRegistry.profile(for: translationRequest.style)
        let context = translationRequest.context ?? .empty
        let contextObject: [String: String] = [
            "chapter_title": context.chapterTitle ?? "",
            "previous_source_block": context.previousSourceText ?? "",
            "previous_translated_block": context.previousTranslation ?? "",
            "next_source_block": context.nextSourceText ?? "",
        ]
        var userObject: [String: Any] = [
            "source_text": translationRequest.sourceText,
            "target_language": translationRequest.targetLanguage,
            "translation_style": profile.styleID,
            "style_prompt_version": profile.version,
            "context": contextObject,
            "glossary": translationRequest.optionalGlossary ?? [:],
            "request_schema_version": ProviderPrompts.schemaVersion,
        ]
        if let correctionReason {
            userObject["correction_instruction"] = correctionInstruction(for: correctionReason)
        }
        let userData = try JSONSerialization.data(withJSONObject: userObject, options: [.sortedKeys])
        guard let userContent = String(data: userData, encoding: .utf8) else {
            throw ProviderError(provider: metadata.providerID, code: .unknownProviderError)
        }

        var payload: [String: Any] = [
            "model": metadata.modelID,
            "messages": [
                ["role": "system", "content": profile.systemPrompt(targetLanguage: translationRequest.targetLanguage)],
                ["role": "user", "content": userContent],
            ],
            "response_format": responseFormat(),
            "temperature": metadata.temperature,
            "stream": false,
        ]
        switch metadata.providerID {
        case .qwen:
            payload["enable_thinking"] = false
        case .deepSeek:
            payload["thinking"] = ["type": "disabled"]
            payload["max_tokens"] = metadata.maxTokens
        }

        let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        var request = URLRequest(url: metadata.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeoutOverride ?? metadata.requestTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = encoded

        let started = Date()
        let (data, response) = try await transport.data(for: request)
        let latency = Int(Date().timeIntervalSince(started) * 1_000)
        guard (200..<300).contains(response.statusCode) else {
            throw classifyHTTPFailure(status: response.statusCode, body: data)
        }

        let envelope = try parseEnvelope(data)
        if envelope.finishReason == "length" {
            throw ProviderError(provider: metadata.providerID, code: .outputTruncated)
        }
        let translation = try parseTranslationContent(envelope.content)
        guard !translation.isEmpty else {
            throw ProviderError(provider: metadata.providerID, code: .emptyResponse)
        }
        guard translation.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains(Int($0.value)) }) else {
            throw ProviderError(provider: metadata.providerID, code: .missingTargetText)
        }
        let residual = TranslationResidualDetector.assessment(of: translation)
        switch residual.severity {
        case .clean, .tolerated:
            break
        case .suspicious where correctionReason == .englishResidual:
            break
        case .suspicious, .severe:
            throw ProviderError(provider: metadata.providerID, code: .englishResidual)
        }

        let diagnostics = ProviderDiagnostics(
            requestID: response.value(forHTTPHeaderField: "x-request-id")
                ?? response.value(forHTTPHeaderField: "request-id"),
            provider: metadata.providerID,
            statusCode: response.statusCode,
            latencyMilliseconds: latency,
            inputCharacters: translationRequest.sourceText.count,
            responseBytes: data.count,
            attempts: attempt
        )
        return TranslationResult(text: translation, metadata: metadata, diagnostics: diagnostics)
    }

    private func validatedCredential(_ credential: String) throws -> String {
        let value = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 8 else {
            throw ProviderError(provider: metadata.providerID, code: .missingCredential)
        }
        return value
    }

    private struct ParsedEnvelope {
        let content: String
        let finishReason: String?
    }

    private func parseEnvelope(_ data: Data) throws -> ParsedEnvelope {
        guard !data.isEmpty else {
            throw ProviderError(provider: metadata.providerID, code: .emptyResponse)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError(provider: metadata.providerID, code: .malformedResponse)
        }
        guard let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderError(provider: metadata.providerID, code: .malformedResponse)
        }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderError(provider: metadata.providerID, code: .emptyResponse)
        }
        return ParsedEnvelope(content: content, finishReason: first["finish_reason"] as? String)
    }

    private func parseTranslationContent(_ content: String) throws -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let unfenced = stripMarkdownFence(from: trimmed)
        var jsonCandidates = [unfenced]
        if let opening = unfenced.firstIndex(of: "{"),
           let closing = unfenced.lastIndex(of: "}"),
           opening < closing {
            let embedded = String(unfenced[opening...closing])
            if embedded != unfenced { jsonCandidates.append(embedded) }
        }

        for candidate in jsonCandidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            for key in ["translation", "translated_text", "translatedText", "text"] {
                if let value = object[key] as? String {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            throw ProviderError(provider: metadata.providerID, code: .malformedResponse)
        }

        if containsChinese(unfenced) {
            return unfenced
        }
        if unfenced.hasPrefix("{") || unfenced.hasSuffix("}") {
            throw ProviderError(provider: metadata.providerID, code: .malformedResponse)
        }
        throw ProviderError(provider: metadata.providerID, code: .missingTargetText)
    }

    private func stripMarkdownFence(from value: String) -> String {
        guard value.hasPrefix("```") else { return value }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3,
              lines.first?.hasPrefix("```") == true,
              lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" else {
            return value
        }
        return lines.dropFirst().dropLast().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsChinese(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x3400...0x9FFF).contains(Int($0.value)) }
    }

    private func isCorrectableOutput(_ code: ProviderErrorCode) -> Bool {
        switch code {
        case .emptyResponse, .malformedResponse, .outputTruncated, .missingTargetText, .englishResidual:
            return true
        default:
            return false
        }
    }

    private func retryLimit(for code: ProviderErrorCode) -> Int {
        code == .outputTruncated ? 0 : (isCorrectableOutput(code) ? 2 : retryMax)
    }

    private func correctionInstruction(for code: ProviderErrorCode) -> String {
        switch code {
        case .emptyResponse:
            return "The previous response was empty. Translate the complete source block into Simplified Chinese and return one non-empty JSON object."
        case .malformedResponse:
            return "The previous response format could not be parsed. Return exactly one JSON object with a string field named translation, with no commentary or markdown fence."
        case .outputTruncated:
            return "The previous response was truncated. Return a complete but concise Simplified Chinese translation in the translation field."
        case .missingTargetText:
            return "The previous response did not contain a Chinese translation. Translate the complete source block into Simplified Chinese and return it in the translation field."
        case .englishResidual:
            return "The previous result contained untranslated ordinary English. Return a complete Chinese translation. Keep only necessary proper names, standard acronyms, URLs, code, and filenames in their original form."
        default:
            return "Retry the complete translation and return one valid JSON object with a translation field."
        }
    }

    private func responseFormat() -> [String: Any] {
        guard metadata.providerID == .qwen else { return ["type": "json_object"] }
        return [
            "type": "json_schema",
            "json_schema": [
                "name": "epub_translation_response",
                "strict": true,
                "schema": [
                    "type": "object",
                    "properties": [
                        "translation": ["type": "string"],
                    ],
                    "required": ["translation"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    private func shouldSubdivide(
        _ code: ProviderErrorCode,
        request: TranslationRequest,
        recoveryDepth: Int
    ) -> Bool {
        guard recoveryDepth < 2, request.sourceText.count > ProviderRecoverySplitter.minimumCharacters else {
            return false
        }
        switch code {
        case .emptyResponse, .malformedResponse, .outputTruncated, .missingTargetText, .englishResidual:
            return true
        default:
            return false
        }
    }

    private func classifyHTTPFailure(status: Int, body: Data) -> ProviderError {
        let code: ProviderErrorCode
        switch status {
        case 401, 403:
            code = .invalidKey
        case 402:
            code = .quotaError
        case 429:
            code = .rateLimit
        case 500...599:
            code = .serverError
        default:
            let safeCode = providerErrorCode(from: body)
            if safeCode.contains("QUOTA") || safeCode.contains("ARREARAGE")
                || safeCode.contains("BALANCE") || safeCode.contains("BILLING") {
                code = .quotaError
            } else {
                code = .providerRefusal
            }
        }
        return ProviderError(provider: metadata.providerID, code: code, httpStatus: status)
    }

    private func providerErrorCode(from body: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return "UNKNOWN" }
        let value = error["code"] ?? error["type"] ?? "UNKNOWN"
        return String(describing: value)
            .uppercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
            .prefix(96)
            .description
    }

    private func classifyTransportFailure(_ error: Error) -> ProviderError {
        guard let urlError = error as? URLError else {
            return ProviderError(provider: metadata.providerID, code: .unknownProviderError)
        }
        switch urlError.code {
        case .timedOut:
            return ProviderError(provider: metadata.providerID, code: .timeout)
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed:
            return ProviderError(provider: metadata.providerID, code: .networkError)
        default:
            return ProviderError(provider: metadata.providerID, code: .unknownProviderError)
        }
    }
}

struct QwenProvider: TranslationProvider {
    let providerID = ProviderID.qwen
    let displayName = "Qwen"
    private let implementation: OpenAICompatibleProvider

    init(transport: ProviderHTTPTransport) throws {
        implementation = try OpenAICompatibleProvider(metadata: .qwen, transport: transport)
    }

    func validateCredential(_ credential: String) async throws -> ProviderDiagnostics {
        try await implementation.validateCredential(credential)
    }

    func translate(
        _ request: TranslationRequest,
        credential: String,
        onRetry: ProviderRetryHandler?
    ) async throws -> TranslationResult {
        try await implementation.translate(request, credential: credential, onRetry: onRetry)
    }
}

struct DeepSeekProvider: TranslationProvider {
    let providerID = ProviderID.deepSeek
    let displayName = "DeepSeek"
    private let implementation: OpenAICompatibleProvider

    init(transport: ProviderHTTPTransport) throws {
        implementation = try OpenAICompatibleProvider(metadata: .deepSeek, transport: transport)
    }

    func validateCredential(_ credential: String) async throws -> ProviderDiagnostics {
        try await implementation.validateCredential(credential)
    }

    func translate(
        _ request: TranslationRequest,
        credential: String,
        onRetry: ProviderRetryHandler?
    ) async throws -> TranslationResult {
        try await implementation.translate(request, credential: credential, onRetry: onRetry)
    }
}

enum ProviderFactory {
    static func make(
        _ provider: ProviderID,
        transport: ProviderHTTPTransport
    ) throws -> any TranslationProvider {
        switch provider {
        case .qwen: return try QwenProvider(transport: transport)
        case .deepSeek: return try DeepSeekProvider(transport: transport)
        }
    }
}

#if DEBUG
final class Stage2UITestTransport: ProviderHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let translation: String
        if body.contains("concise_interpretive") {
            translation = "公司自由现金流上升，但管理层预计明年增长放缓。"
        } else if body.contains("formal_commentary") {
            translation = "公司自由现金流有所增长，然而管理层预期下一年度的增速将趋于放缓。"
        } else if body.contains("literal") {
            translation = "公司增加了自由现金流，但管理层预计明年的增长会更慢。"
        } else {
            translation = "公司的自由现金流有所增长，不过管理层预计明年增速将会放缓。"
        }
        let content = try JSONSerialization.data(
            withJSONObject: ["translation": translation],
            options: [.sortedKeys]
        )
        let envelope: [String: Any] = [
            "choices": [["message": ["content": String(data: content, encoding: .utf8)!]]],
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["x-request-id": "stage2-ui-mock"]
        )!
        return (data, response)
    }
}
#endif

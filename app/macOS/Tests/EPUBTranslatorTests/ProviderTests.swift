import Foundation
import XCTest
@testable import EPUBTranslatorApp

private final class MockProviderTransport: ProviderHTTPTransport {
    typealias Step = (URLRequest) throws -> (Data, HTTPURLResponse)

    private let lock = NSLock()
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []

    init(steps: [Step]) { self.steps = steps }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        requests.append(request)
        guard !steps.isEmpty else {
            lock.unlock()
            throw URLError(.badServerResponse)
        }
        let step = steps.removeFirst()
        lock.unlock()
        return try step(request)
    }
}

private func response(
    for request: URLRequest,
    status: Int = 200,
    content: String? = #"{"translation":"公司的自由现金流有所增长。"}"#,
    finishReason: String? = nil,
    rawData: Data? = nil
) throws -> (Data, HTTPURLResponse) {
    let data: Data
    if let rawData {
        data = rawData
    } else {
        var choice: [String: Any] = ["message": ["content": content ?? ""]]
        if let finishReason { choice["finish_reason"] = finishReason }
        data = try JSONSerialization.data(withJSONObject: [
            "choices": [choice],
        ])
    }
    return (
        data,
        HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["x-request-id": "self-authored-test"]
        )!
    )
}

private let fakeCredential = "FAKE_TEST_SECRET_PROVIDER_123456"
private let translationRequest = TranslationRequest(
    sourceText: ProviderPrompts.translationFixture,
    targetLanguage: "Simplified Chinese",
    style: .fluent,
    context: nil,
    optionalGlossary: ["free cash flow": "自由现金流"]
)

final class ProviderMetadataAndAbstractionTests: XCTestCase {
    func testOfficialProfilesAreCentralizedHTTPSAndNotUserConfigured() throws {
        XCTAssertEqual(ProviderMetadata.qwen.modelID, "qwen3.7-plus")
        XCTAssertEqual(ProviderMetadata.deepSeek.modelID, "deepseek-v4-flash")
        XCTAssertEqual(ProviderMetadata.qwen.endpoint.scheme, "https")
        XCTAssertEqual(ProviderMetadata.deepSeek.endpoint.scheme, "https")
        XCTAssertEqual(ProviderMetadata.qwen.requestTimeout, 45)
        XCTAssertEqual(ProviderMetadata.deepSeek.maxTokens, 4_096)
        try ProviderEndpointPolicy.validate(.qwen)
        try ProviderEndpointPolicy.validate(.deepSeek)
    }

    func testFactoryReturnsOnlyExplicitSelectedProvider() throws {
        let transport = MockProviderTransport(steps: [])
        XCTAssertEqual(try ProviderFactory.make(.qwen, transport: transport).providerID, .qwen)
        XCTAssertEqual(try ProviderFactory.make(.deepSeek, transport: transport).providerID, .deepSeek)
    }

    func testProviderErrorTaxonomyMatchesTechnicalFailures() {
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.invalidKey))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.networkError))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.timeout))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.rateLimit))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.quotaError))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.serverError))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.emptyResponse))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.malformedResponse))
        XCTAssertTrue(ProviderErrorCode.allCases.contains(.outputTruncated))
    }
}

final class TranslationStylePromptTests: XCTestCase {
    func testExactlyFourStylesWithFluentDefaultAndStableIDs() {
        XCTAssertEqual(TranslationStyle.allCases.count, 4)
        XCTAssertEqual(TranslationStylePromptRegistry.defaultStyle, .fluent)
        XCTAssertEqual(
            TranslationStyle.allCases.map(\.rawValue),
            ["literal", "fluent", "concise_interpretive", "formal_commentary"]
        )
        XCTAssertEqual(
            TranslationStylePromptRegistry.profiles.map(\.displayName),
            ["直译版", "通畅版", "意译（更简洁有力）", "书面评论体"]
        )
    }

    func testEveryStyleHasOneDistinctVersionedPromptProfile() {
        let profiles = TranslationStylePromptRegistry.profiles
        XCTAssertEqual(Set(profiles.map(\.styleID)).count, 4)
        XCTAssertEqual(Set(profiles.map(\.promptTemplate)).count, 4)
        XCTAssertTrue(profiles.allSatisfy { $0.version == TranslationStylePromptRegistry.version })
        XCTAssertTrue(profiles.allSatisfy { $0.promptTemplate.contains("only the current source block") })
        XCTAssertTrue(profiles.allSatisfy { $0.promptTemplate.contains("every ordinary English word") })
    }

    func testEveryStyleProducesItsOwnRequestProfile() async throws {
        let transport = MockProviderTransport(steps: TranslationStyle.allCases.map { _ in
            { try response(for: $0) }
        })
        let provider = try QwenProvider(transport: transport)
        for style in TranslationStyle.allCases {
            _ = try await provider.translate(
                TranslationRequest(
                    sourceText: "The market opened calmly.",
                    targetLanguage: "Simplified Chinese",
                    style: style,
                    context: nil,
                    optionalGlossary: nil
                ),
                credential: fakeCredential
            )
        }
        XCTAssertEqual(transport.requests.count, 4)
        let bodies = transport.requests.compactMap { $0.httpBody.flatMap { String(data: $0, encoding: .utf8) } }
        for style in TranslationStyle.allCases {
            XCTAssertTrue(bodies.contains(where: { $0.contains(style.rawValue) }))
        }
    }

    func testStage2MockReturnsFourDistinctChineseResults() async throws {
        let provider = try QwenProvider(transport: Stage2UITestTransport())
        var results: Set<String> = []
        for style in TranslationStyle.allCases {
            let result = try await provider.translate(
                TranslationRequest(
                    sourceText: ProviderPrompts.translationFixture,
                    targetLanguage: "Simplified Chinese",
                    style: style,
                    context: nil,
                    optionalGlossary: nil
                ),
                credential: fakeCredential
            )
            results.insert(result.text)
        }
        XCTAssertEqual(results.count, 4)
    }
}

final class ProviderHappyPathTests: XCTestCase {
    func testTechnicalOnlyUnitsArePreservedWithoutCloudRequest() async throws {
        let preserved = [
            "http://www.gutenberg.org",
            "https://example.com/books/title?id=123",
            "reader" + "@" + "example.org",
            "chapter-01.xhtml",
            "64-6221541",
        ]
        for value in preserved {
            XCTAssertTrue(TranslationPassThroughPolicy.shouldPreserve(value), value)
        }
        XCTAssertFalse(
            TranslationPassThroughPolicy.shouldPreserve("Please visit http://www.gutenberg.org"),
            "Mixed natural-language prose must still be translated"
        )

        let transport = MockProviderTransport(steps: [])
        let request = TranslationRequest(
            sourceText: "http://www.gutenberg.org",
            targetLanguage: "Simplified Chinese",
            style: .literal,
            context: nil,
            optionalGlossary: nil
        )
        let result = try await QwenProvider(transport: transport)
            .translate(request, credential: fakeCredential)

        XCTAssertEqual(result.text, request.sourceText)
        XCTAssertEqual(result.diagnostics.attempts, 0)
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testMixedProseContainingURLStillUsesCloudTranslation() async throws {
        let transport = MockProviderTransport(steps: [{
            try response(for: $0, content: #"{"translation":"请访问 http://www.gutenberg.org。"}"#)
        }])
        let request = TranslationRequest(
            sourceText: "Please visit http://www.gutenberg.org.",
            targetLanguage: "Simplified Chinese",
            style: .literal,
            context: nil,
            optionalGlossary: nil
        )
        let result = try await QwenProvider(transport: transport)
            .translate(request, credential: fakeCredential)

        XCTAssertTrue(result.text.contains("请访问"))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testQwenTranslateParsesJSONObjectAndUsesOnlyQwenCredential() async throws {
        let transport = MockProviderTransport(steps: [{ request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(fakeCredential)")
            XCTAssertEqual(request.url, ProviderMetadata.qwen.endpoint)
            return try response(for: request)
        }])
        let result = try await QwenProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertTrue(result.text.contains("自由现金流"))
        XCTAssertEqual(result.metadata.providerID, .qwen)
        XCTAssertEqual(transport.requests.count, 1)
        let body = try XCTUnwrap(transport.requests[0].httpBody)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let format = try XCTUnwrap(root["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertNil(root["max_tokens"], "Qwen structured output must use the model default to avoid truncating JSON")
        let schemaContainer = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(schemaContainer["strict"] as? Bool, true)
        let schema = try XCTUnwrap(schemaContainer["schema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["translation"])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
    }

    func testDeepSeekTranslateParsesFencedJSONObject() async throws {
        let fenced = "```json\n{\"translation\":\"公司的自由现金流有所增长。\"}\n```"
        let transport = MockProviderTransport(steps: [{ try response(for: $0, content: fenced) }])
        let result = try await DeepSeekProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertTrue(result.text.contains("自由现金流"))
        XCTAssertEqual(result.metadata.providerID, .deepSeek)
        let body = try XCTUnwrap(transport.requests[0].httpBody)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let format = try XCTUnwrap(root["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_object")
        XCTAssertEqual(root["max_tokens"] as? Int, ProviderMetadata.deepSeek.maxTokens)
    }

    func testTruncatedLongUnitIsSubdividedAndRecoveredWithoutStoppingBook() async throws {
        let longText = Array(repeating: "A complete sentence contains important context for translation.", count: 24)
            .joined(separator: " ")
        let pieces = ProviderRecoverySplitter.pieces(from: longText)
        XCTAssertGreaterThan(pieces.count, 1)
        let smallerPieces = ProviderRecoverySplitter.pieces(from: longText, maximumCharacters: 300)
        XCTAssertGreaterThan(smallerPieces.count, pieces.count)
        XCTAssertTrue(smallerPieces.allSatisfy { $0.count <= 300 })
        let steps: [MockProviderTransport.Step] = [
            { try response(for: $0, content: #"{"translation":"截断"}"#, finishReason: "length") },
        ] + pieces.map { _ in
            { try response(for: $0, content: #"{"translation":"这是完整的分段译文。"}"#, finishReason: "stop") }
        }
        let transport = MockProviderTransport(steps: steps)
        let result = try await QwenProvider(transport: transport).translate(
            TranslationRequest(
                sourceText: longText,
                targetLanguage: "Simplified Chinese",
                style: .fluent,
                context: nil,
                optionalGlossary: nil
            ),
            credential: fakeCredential
        )

        XCTAssertEqual(result.text, Array(repeating: "这是完整的分段译文。", count: pieces.count).joined())
        XCTAssertEqual(transport.requests.count, pieces.count + 1)
        XCTAssertTrue(transport.requests.dropFirst().allSatisfy { request in
            guard let body = request.httpBody,
                  let text = String(data: body, encoding: .utf8) else { return false }
            return text.contains("source_text") && !text.contains(longText)
        })
    }

    func testDirectChineseTextAndAlternateKeysAreAccepted() async throws {
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, content: "公司自由现金流有所增长。") },
            { try response(for: $0, content: #"{"translated_text":"管理层预计增长放缓。"}"#) },
            { try response(for: $0, content: "译文如下：\n{\"text\":\"市场平稳开盘。\"}\n以上为译文。") },
        ])
        let provider = try QwenProvider(transport: transport)
        let direct = try await provider.translate(translationRequest, credential: fakeCredential)
        let alternate = try await provider.translate(translationRequest, credential: fakeCredential)
        let embedded = try await provider.translate(translationRequest, credential: fakeCredential)

        XCTAssertEqual(direct.text, "公司自由现金流有所增长。")
        XCTAssertEqual(alternate.text, "管理层预计增长放缓。")
        XCTAssertEqual(embedded.text, "市场平稳开盘。")
        XCTAssertEqual(transport.requests.count, 3)
    }

    func testMalformedOutputSucceedsOnThirdCorrectiveAttempt() async throws {
        let malformed = #"{"unexpected":"wrong shape"}"#
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, content: malformed) },
            { try response(for: $0, content: malformed) },
            { try response(for: $0) },
        ])
        let result = try await DeepSeekProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)

        XCTAssertEqual(result.diagnostics.attempts, 3)
        XCTAssertEqual(transport.requests.count, 3)
        for request in transport.requests.dropFirst() {
            let body = try XCTUnwrap(request.httpBody)
            XCTAssertTrue(String(data: body, encoding: .utf8)?.contains("correction_instruction") == true)
        }
    }

    func testSimpleNeighborContextAndOptionalGlossaryAreSent() async throws {
        let transport = MockProviderTransport(steps: [{ try response(for: $0) }])
        let request = TranslationRequest(
            sourceText: "Margins improved.",
            targetLanguage: "Simplified Chinese",
            style: .formalCommentary,
            context: TranslationContext(
                chapterTitle: "Results",
                previousSourceText: "Revenue grew.",
                previousTranslation: "营收增长。",
                nextSourceText: "Costs declined."
            ),
            optionalGlossary: ["margin": "利润率"]
        )
        _ = try await DeepSeekProvider(transport: transport).translate(request, credential: fakeCredential)
        let body = String(data: transport.requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("previous_source_block"))
        XCTAssertTrue(body.contains("previous_translated_block"))
        XCTAssertTrue(body.contains("next_source_block"))
        XCTAssertTrue(body.contains("margin"))
    }

    func testStandardAcronymDoesNotBlockUsableChinese() async throws {
        let mixed = #"{"translation":"公司发布了 EBITDA，并维持原有展望。"}"#
        let transport = MockProviderTransport(steps: [{ try response(for: $0, content: mixed) }])
        let result = try await QwenProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertTrue(result.text.contains("EBITDA"))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testOneOrTwoOrdinaryEnglishWordsAreToleratedWithoutRetry() async throws {
        let mixed = #"{"translation":"这一段 solely 保持 untouched。"}"#
        let transport = MockProviderTransport(steps: [{ try response(for: $0, content: mixed) }])
        let result = try await QwenProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertTrue(result.text.contains("solely"))
        XCTAssertTrue(result.text.contains("untouched"))
        XCTAssertEqual(result.diagnostics.attempts, 1)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(TranslationResidualDetector.assessment(of: result.text).severity, .tolerated)
    }

    func testOrdinaryEnglishResidualTriggersCorrectiveRetry() async throws {
        let mixed = #"{"translation":"公司需要 improve margin guidance today，并维持原有展望。"}"#
        let corrected = #"{"translation":"公司发布了息税折旧摊销前利润指引，并维持原有展望。"}"#
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, content: mixed) },
            { try response(for: $0, content: corrected) },
        ])
        let result = try await QwenProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertFalse(result.text.contains("guidance"))
        XCTAssertEqual(result.diagnostics.attempts, 2)
        XCTAssertEqual(transport.requests.count, 2)
        let retryBody = try XCTUnwrap(transport.requests.last?.httpBody)
        XCTAssertTrue(String(data: retryBody, encoding: .utf8)?.contains("correction_instruction") == true)
    }

    func testSmallResidualAfterCorrectiveRetryContinuesInsteadOfStoppingBook() async throws {
        let first = #"{"translation":"本段仍有 improve margin guidance today。"}"#
        let second = #"{"translation":"本段仍有 improve margin guidance today。"}"#
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, content: first) },
            { try response(for: $0, content: second) },
        ])
        let result = try await DeepSeekProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertEqual(result.diagnostics.attempts, 2)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(TranslationResidualDetector.assessment(of: result.text).severity, .suspicious)
    }

    func testOrdinaryEnglishResidualFailsAfterTwoCorrectiveRetries() async throws {
        let mixed = #"{"translation":"本段 remains entirely untranslated because the provider returned a full English sentence again。"}"#
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, content: mixed) },
            { try response(for: $0, content: mixed) },
            { try response(for: $0, content: mixed) },
        ])
        do {
            _ = try await QwenProvider(transport: transport)
                .translate(translationRequest, credential: fakeCredential)
            XCTFail("Expected English residual failure")
        } catch let error as ProviderError {
            XCTAssertEqual(error.code, .englishResidual)
            XCTAssertTrue(error.localizedDescription.contains("整句或大段英文"))
        }
        XCTAssertEqual(transport.requests.count, 3)
        XCTAssertEqual(TranslationResidualDetector.assessment(of: "本段 remains entirely untranslated because the provider returned a full English sentence again。").severity, .severe)
    }
}

final class ProviderErrorTaxonomyTests: XCTestCase {
    func test401And403AreInvalidKeyAndNeverRetried() async throws {
        for status in [401, 403] {
            let transport = MockProviderTransport(steps: [{ try response(for: $0, status: status) }])
            do {
                _ = try await DeepSeekProvider(transport: transport)
                    .translate(translationRequest, credential: fakeCredential)
                XCTFail("Expected invalid key")
            } catch let error as ProviderError {
                XCTAssertEqual(error.code, .invalidKey)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testRateLimitAndQuotaAreClassifiedWithoutFallback() async throws {
        for (status, expected) in [(429, ProviderErrorCode.rateLimit), (402, .quotaError)] {
            let transport = MockProviderTransport(steps: [{ try response(for: $0, status: status) }])
            do {
                _ = try await QwenProvider(transport: transport)
                    .translate(translationRequest, credential: fakeCredential)
                XCTFail("Expected provider error")
            } catch let error as ProviderError {
                XCTAssertEqual(error.code, expected)
            }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testServerErrorRetriesAtMostOnceThenSucceeds() async throws {
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, status: 500) },
            { try response(for: $0) },
        ])
        let result = try await QwenProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertEqual(result.diagnostics.attempts, 2)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testServerErrorStopsAfterOneRetry() async throws {
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, status: 500) },
            { try response(for: $0, status: 500) },
        ])
        do {
            _ = try await DeepSeekProvider(transport: transport)
                .translate(translationRequest, credential: fakeCredential)
            XCTFail("Expected server error")
        } catch let error as ProviderError {
            XCTAssertEqual(error.code, .serverError)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testTimeoutAndNetworkRetryOnce() async throws {
        for code in [URLError.Code.timedOut, .notConnectedToInternet] {
            let transport = MockProviderTransport(steps: [
                { _ in throw URLError(code) },
                { _ in throw URLError(code) },
            ])
            do {
                _ = try await QwenProvider(transport: transport)
                    .translate(translationRequest, credential: fakeCredential)
                XCTFail("Expected transport error")
            } catch let error as ProviderError {
                XCTAssertEqual(error.code, code == .timedOut ? .timeout : .networkError)
            }
            XCTAssertEqual(transport.requests.count, 2)
        }
    }

    func testEmptyResponseRetriesOnce() async throws {
        let transport = MockProviderTransport(steps: [
            { try response(for: $0, content: nil) },
            { try response(for: $0) },
        ])
        let result = try await DeepSeekProvider(transport: transport)
            .translate(translationRequest, credential: fakeCredential)
        XCTAssertEqual(result.diagnostics.attempts, 2)
    }

    func testMalformedOuterJSONIsRejectedAfterThreeAttempts() async throws {
        let malformed = MockProviderTransport(steps: (0..<3).map { _ in
            { try response(for: $0, rawData: Data("not-json".utf8)) }
        })
        do {
            _ = try await QwenProvider(transport: malformed)
                .translate(translationRequest, credential: fakeCredential)
            XCTFail("Expected malformed response")
        } catch let error as ProviderError {
            XCTAssertEqual(error.code, .malformedResponse)
        }
        XCTAssertEqual(malformed.requests.count, 3)
    }

    func testNoChineseTargetIsTechnicalFailure() async throws {
        let echo = #"{"translation":"The market opened calmly."}"#
        let transport = MockProviderTransport(steps: (0..<3).map { _ in
            { try response(for: $0, content: echo) }
        })
        do {
            _ = try await DeepSeekProvider(transport: transport)
                .translate(translationRequest, credential: fakeCredential)
            XCTFail("Expected missing target text")
        } catch let error as ProviderError {
            XCTAssertEqual(error.code, .missingTargetText)
        }
        XCTAssertEqual(transport.requests.count, 3)
    }
}

final class ProviderIsolationTests: XCTestCase {
    func testSelectedProviderFailureNeverTriggersOtherProvider() async throws {
        let qwenTransport = MockProviderTransport(steps: [{ try response(for: $0, status: 401) }])
        let deepSeekTransport = MockProviderTransport(steps: [{ try response(for: $0) }])
        let qwen = try QwenProvider(transport: qwenTransport)
        _ = try DeepSeekProvider(transport: deepSeekTransport)
        do {
            _ = try await qwen.translate(translationRequest, credential: fakeCredential)
            XCTFail("Expected Qwen error")
        } catch let error as ProviderError {
            XCTAssertEqual(error.provider, .qwen)
            XCTAssertEqual(error.code, .invalidKey)
        }
        XCTAssertEqual(qwenTransport.requests.count, 1)
        XCTAssertEqual(deepSeekTransport.requests.count, 0)
    }

    func testRawCredentialCannotEnterHelperPayload() throws {
        let encoded = try JSONEncoder().encode(HelperRequest(command: "ping", delayMilliseconds: nil))
        let text = String(data: encoded, encoding: .utf8)!
        XCTAssertFalse(text.contains(fakeCredential))
        XCTAssertFalse(text.lowercased().contains("credential"))
        XCTAssertFalse(text.lowercased().contains("api_key"))
        let helperObject = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        XCTAssertEqual(Set(helperObject.keys), ["command"])
    }
}

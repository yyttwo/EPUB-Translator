import AppKit
import XCTest

final class LocalAcceptanceUITests: XCTestCase {
    private var app: XCUIApplication!
    private var localFixtureURL: URL!
    private var localFixtureDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        localFixtureURL = try materializeFixture()
        app = XCUIApplication()
        app.launchEnvironment["EPUB_TRANSLATOR_UI_TESTING"] = "1"
        app.launchEnvironment["EPUB_TRANSLATOR_UI_FIXTURE"] = localFixtureURL.path
        app.launchArguments = ["--ui-testing", "--stage2-ui-mock"]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let localFixtureEmittedDirectory = localFixtureDirectory {
            try? FileManager.default.removeItem(at: localFixtureEmittedDirectory)
        }
    }

    func testAPIFieldsAndBookProgressPresentation() throws {
        launchMainWindow()
        XCTAssertTrue(waitForPrefix(
            "已识别 1 个正文文件、4 个翻译单元",
            element: app.staticTexts["statusMessage"]
        ))

        openAPIManager()
        XCTAssertFalse(app.textFields["apiNameTextField"].exists)
        XCTAssertTrue(app.popUpButtons["apiProviderPicker"].exists)
        XCTAssertTrue(app.secureTextFields["apiKeySecureField"].exists)
        XCTAssertTrue(app.buttons["saveAPIButton"].exists)
        XCTAssertFalse(app.checkBoxes["saveToKeychainToggle"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "不会读取或写入 macOS 钥匙串", "不会读取或写入 macOS 钥匙串"
        )).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["开发验证 · 自写短句"].exists)
        XCTAssertFalse(app.buttons["runTranslationButton"].exists)

        openTranslationPage()
        XCTAssertTrue(app.staticTexts["bookUnitSummary"].exists)
        XCTAssertTrue(waitForLabel("0%", element: app.staticTexts["translationPercentage"]))
        XCTAssertTrue(app.staticTexts["translationUnitProgress"].exists)
        XCTAssertTrue(app.staticTexts["estimatedTranslationTime"].exists)
        XCTAssertTrue(app.progressIndicators["translationProgressBar"].exists)
    }

    func testSaveValidateAndTranslateFlow() throws {
        launchMainWindow()
        openAPIManager()
        removeSavedAPIsIfPresent()

        enterAPI(provider: "Qwen", key: "fakeqwen12345678")
        XCTAssertTrue(waitForLabel("已配置", element: app.staticTexts["credentialState-Qwen"]))
        XCTAssertTrue(app.buttons["validateCredential-Qwen"].exists)

        openTranslationPage()
        app.buttons["startTranslationButton"].click()
        XCTAssertTrue(waitForLabel("100%", element: app.staticTexts["translationPercentage"]))
        XCTAssertTrue(app.staticTexts["statusMessage"].exists)
        XCTAssertTrue(app.staticTexts["translatedTextPreview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveTranslatedEPUBButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["revealTranslatedEPUBButton"].waitForExistence(timeout: 5))

    }

    func testKeysAreSessionOnlyAndUserCanReenterAfterRestart() throws {
        launchMainWindow()
        openAPIManager()
        removeSavedAPIsIfPresent()
        XCTAssertTrue(waitForLabel("未配置", element: app.staticTexts["credentialState-Qwen"]))
        XCTAssertTrue(waitForLabel("未配置", element: app.staticTexts["credentialState-DeepSeek"]))

        XCTAssertFalse(app.staticTexts["开发验证 · 自写短句"].exists)
        XCTAssertFalse(app.buttons["runTranslationButton"].exists)

        enterAPI(provider: "Qwen", key: "fakeqwen12345678")
        enterAPI(provider: "DeepSeek", key: "fakedeepseek12345678")
        XCTAssertTrue(waitForLabel("已配置", element: app.staticTexts["credentialState-Qwen"]))
        XCTAssertTrue(waitForLabel("已配置", element: app.staticTexts["credentialState-DeepSeek"]))
        XCTAssertTrue(app.staticTexts["credentialPersistence-Qwen"].exists)
        XCTAssertTrue(app.staticTexts["credentialPersistence-DeepSeek"].exists)

        let revalidateQwen = app.buttons["validateCredential-Qwen"]
        XCTAssertTrue(revalidateQwen.exists)
        revalidateQwen.click()
        XCTAssertTrue(
            app.buttons["validateCredential-Qwen"].waitForExistence(timeout: 1),
            "重新验证期间，已保存的 API 操作按钮不应从界面消失"
        )
        XCTAssertTrue(waitForLabel("已配置", element: app.staticTexts["credentialState-Qwen"]))

        app.terminate()
        launchMainWindow()
        openAPIManager()
        XCTAssertTrue(waitForLabel("未配置", element: app.staticTexts["credentialState-Qwen"]))
        XCTAssertTrue(waitForLabel("未配置", element: app.staticTexts["credentialState-DeepSeek"]))
        openTranslationPage()
        selectProvider("Qwen")
        app.buttons["startTranslationButton"].click()
        XCTAssertTrue(waitForLabel("还没有配置 AI 服务", element: app.staticTexts["userErrorTitle"]))

        openAPIManager()
        enterAPI(provider: "Qwen", key: "fakeqwenreentered87654321")
        XCTAssertTrue(waitForLabel("已配置", element: app.staticTexts["credentialState-Qwen"]))
        openTranslationPage()
        app.buttons["startTranslationButton"].click()
        XCTAssertTrue(waitForLabel("100%", element: app.staticTexts["translationPercentage"]))
    }

    func testSelectEPUBAndMissingAPIMessage() throws {
        app.launchEnvironment.removeValue(forKey: "EPUB_TRANSLATOR_UI_FIXTURE")
        launchMainWindow()
        openAPIManager()
        removeSavedAPIsIfPresent()
        openTranslationPage()

        chooseEPUB(at: localFixtureURL)
        XCTAssertTrue(app.staticTexts["selectedFileName"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel("0%", element: app.staticTexts["translationPercentage"]))
        XCTAssertTrue(app.staticTexts["translationUnitProgress"].exists)
        app.buttons["startTranslationButton"].click()
        XCTAssertTrue(waitForLabel("还没有配置 AI 服务", element: app.staticTexts["userErrorTitle"]))
        XCTAssertTrue(app.staticTexts["userErrorMessage"].exists)
        XCTAssertTrue(app.staticTexts["userErrorRecoveryHint"].exists)
        XCTAssertFalse(app.staticTexts["HTTP 401 Unauthorized"].exists)
        app.buttons["userErrorPrimaryAction"].click()
        XCTAssertTrue(app.staticTexts["apiManagerTitle"].waitForExistence(timeout: 5))
    }

    func testTimeoutErrorCardPreservesProgressAndCopiesRedactedDiagnostics() throws {
        app.launchEnvironment["EPUB_TRANSLATOR_UI_ERROR"] = "timeout"
        launchMainWindow()

        XCTAssertTrue(waitForLabel("AI 服务响应超时", element: app.staticTexts["userErrorTitle"]))
        XCTAssertTrue(app.staticTexts["userErrorMessage"].exists)
        XCTAssertTrue(app.staticTexts["userErrorRecoveryHint"].exists)
        XCTAssertTrue(app.staticTexts["userErrorProgress"].exists)
        XCTAssertTrue(app.buttons["userErrorPrimaryAction"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] 'NSURLError' OR value CONTAINS[c] 'NSURLError'"
        )).firstMatch.exists)

        let details = app.buttons["errorDetailsButton"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.click()
        let copy = app.buttons["copyDiagnosticsButton"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.click()

        let report = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(report.contains("Error Code: PROVIDER_TIMEOUT"))
        XCTAssertTrue(report.contains("Progress: 0/4"))
        XCTAssertFalse(report.contains(["", "Users", ""].joined(separator: "/")))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("api key"))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("bearer"))
    }

    func testInvalidKeyErrorExplainsRecoveryAndOpensAPIManager() throws {
        app.launchEnvironment["EPUB_TRANSLATOR_UI_ERROR"] = "invalid_key"
        launchMainWindow()

        XCTAssertTrue(waitForLabel("Qwen API Key 无效", element: app.staticTexts["userErrorTitle"]))
        XCTAssertTrue(app.staticTexts["userErrorMessage"].exists)
        XCTAssertTrue(app.staticTexts["userErrorRecoveryHint"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS[c] 'HTTP 401' OR value CONTAINS[c] 'HTTP 401'"
        )).firstMatch.exists)
        app.buttons["userErrorPrimaryAction"].click()
        XCTAssertTrue(app.staticTexts["apiManagerTitle"].waitForExistence(timeout: 5))
    }

    func testHelpPageProvidesUserInitiatedGitHubFeedbackEntry() throws {
        launchMainWindow()
        let helpItem = app.buttons["sidebarHelp"]
        XCTAssertTrue(helpItem.waitForExistence(timeout: 5))
        helpItem.click()
        XCTAssertTrue(app.staticTexts["helpTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["helpFeedbackButton"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "不会自动上传日志", "不会自动上传日志"
        )).firstMatch.exists)
    }

    private func enterAPI(provider: String, key: String) {
        app.activate()
        let providerPicker = app.popUpButtons["apiProviderPicker"]
        XCTAssertTrue(providerPicker.waitForExistence(timeout: 5))
        if (providerPicker.value as? String) != provider {
            providerPicker.click()
            let item = app.menuItems[provider]
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            item.click()
            XCTAssertTrue(waitForValue(provider, element: providerPicker))
        }
        let keyField = app.secureTextFields["apiKeySecureField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 5))
        pasteSecureText(key, into: keyField)
        XCTAssertTrue(app.buttons["saveAPIButton"].exists)
        keyField.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(waitForPrefix("\(provider) 验证通过", element: app.staticTexts["apiManagerStatus"]))
        XCTAssertTrue(waitForLabel("已配置", element: app.staticTexts["credentialState-\(provider)"]))
    }

    private func removeSavedAPIsIfPresent() {
        app.activate()
        for provider in ["Qwen", "DeepSeek"] {
            let delete = app.buttons["deleteCredential-\(provider)"]
            if delete.exists { deleteAPI(provider) }
        }
    }

    private func deleteAPI(_ provider: String) {
        let delete = app.buttons["deleteCredential-\(provider)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.click()
        let confirm = app.sheets.buttons["删除 \(provider) API Key"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.click()
        XCTAssertTrue(waitForLabel("未配置", element: app.staticTexts["credentialState-\(provider)"]))
    }

    private func validateAPI(_ provider: String) {
        let button = app.buttons["validateCredential-\(provider)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        XCTAssertTrue(waitForLabel("验证通过", element: app.staticTexts["credentialState-\(provider)"]))
    }

    private func openAPIManager() {
        app.activate()
        let title = app.staticTexts["apiManagerTitle"]
        let sidebarItem = app.buttons["sidebarAPIManager"]
        if !sidebarItem.waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(sidebarItem.waitForExistence(timeout: 10))
        }
        sidebarItem.click()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    private func openTranslationPage() {
        app.activate()
        let title = app.staticTexts["appTitle"]
        let sidebarItem = app.buttons["sidebarTranslation"]
        if !sidebarItem.waitForExistence(timeout: 3) {
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(sidebarItem.waitForExistence(timeout: 10))
        }
        sidebarItem.click()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
    }

    private func launchMainWindow() {
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let title = app.staticTexts["appTitle"]
        if !title.waitForExistence(timeout: 2) {
            app.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(title.waitForExistence(timeout: 10))
    }

    private func selectProvider(_ name: String) {
        app.activate()
        let picker = app.popUpButtons["providerPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.click()
        let item = app.menuItems[name]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
    }

    private func chooseEPUB(at url: URL) {
        app.activate()
        app.buttons["chooseEPUBButton"].click()
        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let locationField = app.sheets.textFields.firstMatch
        XCTAssertTrue(locationField.waitForExistence(timeout: 5))
        locationField.typeText(url.path)
        locationField.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(
            waitForNonexistence(locationField, timeout: 10),
            "文件路径确认框未在限定时间内关闭"
        )
        if panel.exists {
            app.typeKey(.enter, modifierFlags: [])
        }
        XCTAssertTrue(waitForNonexistence(panel, timeout: 5))
    }

    private func pasteSecureText(_ text: String, into element: XCUIElement) {
        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        defer {
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                _ = pasteboard.writeObjects(savedItems)
            }
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        element.click()
        element.typeKey("v", modifierFlags: .command)
    }

    private func materializeFixture() throws -> URL {
        var repositoryRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            repositoryRoot.deleteLastPathComponent()
        }

        let source = repositoryRoot
            .appendingPathComponent("fixtures", isDirectory: true)
            .appendingPathComponent("stage-1-self-authored.epub")
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EPUBTranslatorUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let destination = destinationDirectory.appendingPathComponent("stage-1-self-authored.epub")
        try FileManager.default.copyItem(at: source, to: destination)
        localFixtureDirectory = destinationDirectory
        return destination
    }

    private func waitForLabel(_ label: String, element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label == %@ OR value == %@", label, label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 8) == .completed
    }

    private func waitForPrefix(_ prefix: String, element: XCUIElement) -> Bool {
        let predicate = NSPredicate(
            format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    private func waitForValue(_ value: String, element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func waitForNonexistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

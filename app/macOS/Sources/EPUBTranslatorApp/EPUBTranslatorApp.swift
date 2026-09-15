import AppKit
import SwiftUI

@main
struct EPUBTranslatorApp: App {
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--ui-light-preview") {
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        }
        Self.runProbeIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup("EPUB翻译") {
            rootContent
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("导航") {
                Button("翻译") {
                    NotificationCenter.default.post(name: .showTranslationPage, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("API 管理") {
                    NotificationCenter.default.post(name: .showAPIManagerPage, object: nil)
                }
                .keyboardShortcut("2", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("反馈问题…") { SupportLinks.openIssues() }
            }
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if Self.isHostedUnitTest {
            EmptyView()
        } else if CommandLine.arguments.contains("--ui-light-preview") {
            ContentView().preferredColorScheme(.light)
        } else {
            ContentView()
        }
        #else
        ContentView()
        #endif
    }

    #if DEBUG
    private static var isHostedUnitTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            && ProcessInfo.processInfo.environment["EPUB_TRANSLATOR_UI_TESTING"] != "1"
    }

    private static func runProbeIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else { return }
        switch arguments[1] {
        case "--stage1-helper-ping":
            do {
                let response = try HelperClient.bundled().pingSynchronously(timeout: 2)
                print(response.ok && response.value == "pong" ? "HELPER_PING_PASS" : "HELPER_INVALID_RESPONSE")
                exit(response.ok && response.value == "pong" ? 0 : 2)
            } catch {
                print("HELPER_PING_FAIL")
                exit(2)
            }
        case "--stage1-helper-timeout":
            do {
                _ = try HelperClient.bundled().pingSynchronously(timeout: 0.05, delayMilliseconds: 500)
                print("HELPER_TIMEOUT_FAIL")
                exit(2)
            } catch HelperClientError.timeout {
                print("HELPER_TIMEOUT_PASS")
                exit(0)
            } catch {
                print("HELPER_TIMEOUT_WRONG_ERROR")
                exit(2)
            }
        case "--stage1-helper-not-available":
            let missingURL = Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("MissingStage1Helper")
            do {
                _ = try HelperClient(executableURL: missingURL).pingSynchronously(timeout: 0.05)
                print("HELPER_NOT_AVAILABLE_FAIL")
                exit(2)
            } catch HelperClientError.notAvailable {
                print("HELPER_NOT_AVAILABLE_PASS")
                exit(0)
            } catch {
                print("HELPER_NOT_AVAILABLE_WRONG_ERROR")
                exit(2)
            }
        case "--stage1-helper-exited":
            do {
                _ = try HelperClient.bundled().exitProbeSynchronously(timeout: 2)
                print("HELPER_EXITED_FAIL")
                exit(2)
            } catch HelperClientError.exited(23) {
                print("HELPER_EXITED_PASS")
                exit(0)
            } catch {
                print("HELPER_EXITED_WRONG_ERROR")
                exit(2)
            }
        case "--stage1-probe-read" where arguments.count == 3:
            do {
                _ = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
                print("UNAUTHORIZED_READ_SUCCEEDED")
                exit(2)
            } catch {
                print("ACCESS_DENIED")
                exit(0)
            }
        case "--stage1-probe-write" where arguments.count == 3:
            do {
                try Data("stage-1-probe".utf8).write(
                    to: URL(fileURLWithPath: arguments[2]), options: .atomic)
                print("UNAUTHORIZED_WRITE_SUCCEEDED")
                exit(2)
            } catch {
                print("ACCESS_DENIED")
                exit(0)
            }
        default:
            return
        }
    }
    #endif
}

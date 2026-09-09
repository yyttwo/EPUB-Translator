import Foundation

struct HelperRequest: Codable {
    let command: String
    let delayMilliseconds: Int?
}

struct HelperResponse: Codable, Equatable {
    let ok: Bool
    let value: String?
    let error: String?
}

enum HelperClientError: LocalizedError, Equatable {
    case notAvailable
    case launchFailed
    case timeout
    case exited(Int32)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "Core Helper 不可用。"
        case .launchFailed: return "Core Helper 无法启动。"
        case .timeout: return "Core Helper 响应超时。"
        case .exited: return "Core Helper 意外退出。"
        case .invalidResponse: return "Core Helper 返回了无效响应。"
        }
    }
}

final class HelperClient {
    private let executableURL: URL

    init(executableURL: URL) {
        self.executableURL = executableURL
    }

    static func bundled() -> HelperClient {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent(AppIdentity.helperName)
        return HelperClient(executableURL: url)
    }

    func ping(timeout: TimeInterval = 2, delayMilliseconds: Int? = nil) async throws -> HelperResponse {
        try await Task.detached(priority: .userInitiated) {
            try self.pingSynchronously(timeout: timeout, delayMilliseconds: delayMilliseconds)
        }.value
    }

    func pingSynchronously(timeout: TimeInterval = 2, delayMilliseconds: Int? = nil) throws -> HelperResponse {
        try requestSynchronously(command: "ping", timeout: timeout, delayMilliseconds: delayMilliseconds)
    }

    func exitProbeSynchronously(timeout: TimeInterval = 2) throws -> HelperResponse {
        try requestSynchronously(command: "exit", timeout: timeout)
    }

    private func requestSynchronously(
        command: String,
        timeout: TimeInterval,
        delayMilliseconds: Int? = nil
    ) throws -> HelperResponse {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw HelperClientError.notAvailable
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = executableURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

        let request = HelperRequest(command: command, delayMilliseconds: delayMilliseconds)
        let encoded = try JSONEncoder().encode(request) + Data([0x0A])
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do { try process.run() } catch { throw HelperClientError.launchFailed }
        input.fileHandleForWriting.write(encoded)
        try? input.fileHandleForWriting.close()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            _ = finished.wait(timeout: .now() + 1)
            throw HelperClientError.timeout
        }

        let data = try output.fileHandleForReading.readToEnd() ?? Data()
        guard process.terminationStatus == 0 else {
            throw HelperClientError.exited(process.terminationStatus)
        }
        guard let line = data.split(separator: 0x0A).first,
              let response = try? JSONDecoder().decode(HelperResponse.self, from: Data(line)) else {
            throw HelperClientError.invalidResponse
        }
        return response
    }
}

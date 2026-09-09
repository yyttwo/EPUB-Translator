import Foundation

struct HelperRequest: Codable {
    let command: String
    let delayMilliseconds: Int?
}

struct HelperResponse: Codable {
    let ok: Bool
    let value: String?
    let error: String?
}

func write(_ response: HelperResponse) {
    guard let data = try? JSONEncoder().encode(response) else { exit(3) }
    FileHandle.standardOutput.write(data + Data([0x0A]))
}

guard let line = readLine(), let data = line.data(using: .utf8),
      let request = try? JSONDecoder().decode(HelperRequest.self, from: data) else {
    write(HelperResponse(ok: false, value: nil, error: "INVALID_REQUEST"))
    exit(2)
}

if let delay = request.delayMilliseconds, delay > 0 {
    Thread.sleep(forTimeInterval: Double(min(delay, 10_000)) / 1_000)
}

if request.command == "exit" {
    exit(23)
}

guard request.command == "ping" else {
    write(HelperResponse(ok: false, value: nil, error: "UNKNOWN_COMMAND"))
    exit(0)
}

write(HelperResponse(ok: true, value: "pong", error: nil))

import Foundation

enum SecretRedactor {
    static func redact(_ text: String, knownSecrets: [String] = []) -> String {
        var value = text
        for secret in knownSecrets where !secret.isEmpty {
            value = value.replacingOccurrences(of: secret, with: "[REDACTED]")
        }
        let patterns = [
            #"(?i)(authorization\s*:\s*bearer\s+)[^\s]+"#,
            #"(?i)(api[_-]?key["']?\s*[=:]\s*["']?)[^\s"',;}]+"#,
            #"(?i)sk-[A-Za-z0-9_-]{8,}"#,
        ]
        for pattern in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: pattern.hasPrefix("(?i)sk-") ? "[REDACTED]" : "$1[REDACTED]",
                options: .regularExpression
            )
        }
        return value
    }
}

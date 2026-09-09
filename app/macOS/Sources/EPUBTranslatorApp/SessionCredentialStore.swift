import Foundation

enum CredentialPersistence: Equatable {
    case sessionOnly
}

protocol CredentialStoring: AnyObject {
    func saveSecret(
        _ secret: String,
        for provider: ProviderID,
        persistence: CredentialPersistence
    ) throws
    func readSecret(for provider: ProviderID) throws -> String?
    func hasSecret(for provider: ProviderID) throws -> Bool
    func persistence(for provider: ProviderID) throws -> CredentialPersistence?
    func deleteSecret(for provider: ProviderID) throws
}

extension CredentialStoring {
    func saveSecret(_ secret: String, for provider: ProviderID) throws {
        try saveSecret(secret, for: provider, persistence: .sessionOnly)
    }
}

enum CredentialStoreError: LocalizedError, Equatable {
    case invalidSecret
    case readFailed
    case updateFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "API Key 格式无效，请输入至少 8 个字符。"
        case .readFailed:
            return "无法读取本次运行中的 API Key，请重新输入并验证。"
        case .updateFailed:
            return "无法更新本次运行中的 API Key，原有密钥未被替换。"
        case .deleteFailed:
            return "无法删除本次运行中的 API Key，请重试。"
        }
    }
}

/// Holds user-entered API keys only in this App process. Nothing is persisted to disk.
final class SessionCredentialStore: CredentialStoring {
    private var values: [ProviderID: String] = [:]

    func saveSecret(
        _ secret: String,
        for provider: ProviderID,
        persistence: CredentialPersistence = .sessionOnly
    ) throws {
        guard secret.count >= 8 else { throw CredentialStoreError.invalidSecret }
        values[provider] = secret
    }

    func readSecret(for provider: ProviderID) throws -> String? { values[provider] }
    func hasSecret(for provider: ProviderID) throws -> Bool { values[provider] != nil }
    func persistence(for provider: ProviderID) throws -> CredentialPersistence? {
        values[provider] == nil ? nil : .sessionOnly
    }
    func deleteSecret(for provider: ProviderID) throws { values.removeValue(forKey: provider) }
}

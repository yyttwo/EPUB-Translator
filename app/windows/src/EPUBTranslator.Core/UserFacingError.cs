namespace EPUBTranslator.Core;

public sealed record UserFacingError(
    string Title,
    string Message,
    string RecoveryHint,
    string TechnicalCode);

public static class UserFacingErrors
{
    public static UserFacingError FileReadFailed() => new(
        "无法读取电子书",
        "所选文件无法读取。",
        "请确认文件仍然存在、拥有读取权限，并重新选择 EPUB。",
        "WIN_FILE_READ_FAILED");

    public static UserFacingError FileSaveFailed() => new(
        "无法保存文件",
        "测试副本没有写入到所选位置。",
        "请选择另一个位置，并确认磁盘空间和写入权限。",
        "WIN_FILE_SAVE_FAILED");

    public static UserFacingError CredentialFailed() => new(
        "API Key 操作失败",
        "Windows 凭据管理器未能完成该操作。",
        "请重试；如果问题持续，请检查当前 Windows 账户的凭据服务。",
        "WIN_CREDENTIAL_FAILED");

    public static UserFacingError ProviderNotConfigured() => new(
        "尚未配置 API Key",
        "当前云端 AI 尚未配置。",
        "请前往“API 管理”添加该服务的 API Key。",
        "WIN_PROVIDER_NOT_CONFIGURED");

    public static UserFacingError ProviderRequestFailed(ProviderRequestException exception) =>
        exception.Category switch
        {
            ProviderErrorCategory.MissingCredential => ProviderNotConfigured(),
            ProviderErrorCategory.InvalidCredentialFormat => new(
                "API Key 格式无效",
                $"{exception.Provider.DisplayName()} API Key 包含不允许的空格、标点或复制字符。",
                "请只粘贴服务商生成的 Key 本身，不要包含逗号、引号或换行。",
                "WIN_PROVIDER_CREDENTIAL_FORMAT"),
            ProviderErrorCategory.Authentication => new(
                "API Key 无效",
                $"{exception.Provider.DisplayName()} 拒绝了当前 API Key。",
                "请检查 Key 后更换，并重新验证。",
                "WIN_PROVIDER_AUTHENTICATION"),
            ProviderErrorCategory.Permission => new(
                "API 权限不足",
                $"当前 Key 无权调用 {exception.Provider.DisplayName()} 模型。",
                "请在服务商控制台检查模型权限和账户状态。",
                "WIN_PROVIDER_PERMISSION"),
            ProviderErrorCategory.RateLimit => new(
                "请求受限",
                $"{exception.Provider.DisplayName()} 返回了额度或频率限制。",
                "请检查账户额度，稍后再试。",
                "WIN_PROVIDER_RATE_LIMIT"),
            ProviderErrorCategory.ProviderService => new(
                "服务暂时不可用",
                $"{exception.Provider.DisplayName()} 未能完成请求。",
                "请稍后重试；应用不会自动切换到其他服务商。",
                "WIN_PROVIDER_SERVICE"),
            ProviderErrorCategory.Network => new(
                "网络连接失败",
                $"无法连接到 {exception.Provider.DisplayName()}。",
                "请检查 HTTPS 网络连接后重试。",
                "WIN_PROVIDER_NETWORK"),
            ProviderErrorCategory.Timeout => new(
                "请求超时",
                $"{exception.Provider.DisplayName()} 在限定时间内没有完成请求。",
                "请稍后重试；已保存的配置不会丢失。",
                "WIN_PROVIDER_TIMEOUT"),
            ProviderErrorCategory.Cancelled => new(
                "请求已取消",
                "当前 AI 请求已经停止。",
                "可以随时重新验证或再次运行翻译测试。",
                "WIN_PROVIDER_CANCELLED"),
            ProviderErrorCategory.EmptyResponse => new(
                "服务返回空响应",
                $"{exception.Provider.DisplayName()} 没有返回可用内容。",
                "请稍后重新验证或再次测试。",
                "WIN_PROVIDER_EMPTY_RESPONSE"),
            ProviderErrorCategory.OutputTruncated => new(
                "响应被截断",
                $"{exception.Provider.DisplayName()} 的输出没有完整结束。",
                "请稍后重新测试。",
                "WIN_PROVIDER_OUTPUT_TRUNCATED"),
            ProviderErrorCategory.MalformedResponse => new(
                "响应格式异常",
                $"{exception.Provider.DisplayName()} 返回了无法解析的内容。",
                "请稍后重新验证；问题持续时可复制脱敏诊断。",
                "WIN_PROVIDER_MALFORMED_RESPONSE"),
            _ => throw new ArgumentOutOfRangeException(nameof(exception), exception.Category, null),
        };

    public static UserFacingError FromException(Exception exception, string stage) => stage switch
    {
        "open" => FileReadFailed(),
        "save" => FileSaveFailed(),
        "credential" => CredentialFailed(),
        _ => new(
            "操作没有完成",
            "应用遇到了一个无法继续的错误。",
            "请重试；问题持续时可从“关于与帮助”反馈。",
            $"WIN_{stage.ToUpperInvariant()}_{exception.GetType().Name.ToUpperInvariant()}"),
    };
}

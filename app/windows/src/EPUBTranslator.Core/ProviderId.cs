namespace EPUBTranslator.Core;

public enum ProviderId
{
    Qwen,
    DeepSeek,
}

public static class ProviderIdentity
{
    public static string DisplayName(this ProviderId provider) => provider switch
    {
        ProviderId.Qwen => "Qwen",
        ProviderId.DeepSeek => "DeepSeek",
        _ => throw new ArgumentOutOfRangeException(nameof(provider), provider, null),
    };

    public static string CredentialTarget(this ProviderId provider) =>
        $"EPUBTranslator.Windows/{provider.DisplayName()}";
}

namespace EPUBTranslator.Core;

public sealed class ProviderCoordinator
{
    private readonly ICredentialStore _credentialStore;
    private readonly Dictionary<ProviderId, ITranslationProvider> _providers;

    public ProviderCoordinator(
        ICredentialStore credentialStore,
        IEnumerable<ITranslationProvider> providers)
    {
        _credentialStore = credentialStore ?? throw new ArgumentNullException(nameof(credentialStore));
        ArgumentNullException.ThrowIfNull(providers);
        _providers = providers.ToDictionary(provider => provider.Provider);

        foreach (var provider in Enum.GetValues<ProviderId>())
        {
            if (!_providers.ContainsKey(provider))
            {
                throw new ArgumentException($"Missing provider implementation: {provider}.", nameof(providers));
            }
        }
    }

    public async ValueTask<ProviderValidationResult> ValidateCredentialAsync(
        ProviderId provider,
        CancellationToken cancellationToken = default)
    {
        var credential = await ReadCredentialAsync(provider, cancellationToken).ConfigureAwait(false);
        try
        {
            return await Resolve(provider)
                .ValidateCredentialAsync(credential, cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            credential = string.Empty;
        }
    }

    public async ValueTask<ProviderTranslationResult> TranslateAsync(
        ProviderId provider,
        string sourceText,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceText);
        var credential = await ReadCredentialAsync(provider, cancellationToken).ConfigureAwait(false);
        try
        {
            return await Resolve(provider)
                .TranslateAsync(sourceText, credential, cancellationToken)
                .ConfigureAwait(false);
        }
        finally
        {
            credential = string.Empty;
        }
    }

    private ITranslationProvider Resolve(ProviderId provider) =>
        _providers.TryGetValue(provider, out var implementation)
            ? implementation
            : throw new ArgumentOutOfRangeException(nameof(provider), provider, null);

    private async ValueTask<string> ReadCredentialAsync(
        ProviderId provider,
        CancellationToken cancellationToken)
    {
        var credential = await _credentialStore.ReadAsync(provider, cancellationToken).ConfigureAwait(false);
        if (string.IsNullOrWhiteSpace(credential))
        {
            throw new ProviderRequestException(provider, ProviderErrorCategory.MissingCredential);
        }

        return credential;
    }
}

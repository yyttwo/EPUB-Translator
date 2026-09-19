using EPUBTranslator.Core;

namespace EPUBTranslator.App;

internal sealed class ProviderSessionState
{
    private readonly HashSet<ProviderId> _validated = [];
    private readonly Dictionary<ProviderId, int> _requestCounts = [];

    public bool IsValidated(ProviderId provider) => _validated.Contains(provider);

    public int RequestCount(ProviderId provider) => _requestCounts.GetValueOrDefault(provider);

    public void MarkValidated(ProviderId provider) => _validated.Add(provider);

    public void Invalidate(ProviderId provider) => _validated.Remove(provider);

    public void RecordRequest(ProviderId provider) =>
        _requestCounts[provider] = RequestCount(provider) + 1;
}

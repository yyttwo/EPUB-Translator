namespace EPUBTranslator.Core;

public enum ProviderErrorCategory
{
    MissingCredential,
    InvalidCredentialFormat,
    Authentication,
    Permission,
    RateLimit,
    ProviderService,
    Network,
    Timeout,
    Cancelled,
    EmptyResponse,
    MalformedResponse,
    OutputTruncated,
}

public sealed record ProviderProfile(
    ProviderId Provider,
    string Model,
    Uri Endpoint,
    TimeSpan ValidationTimeout,
    TimeSpan TranslationTimeout,
    int MaximumOutputTokens);

public static class ProviderProfiles
{
    public static ProviderProfile Qwen { get; } = new(
        ProviderId.Qwen,
        "qwen3.7-plus",
        new Uri("https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"),
        TimeSpan.FromSeconds(15),
        TimeSpan.FromSeconds(45),
        4_096);

    public static ProviderProfile DeepSeek { get; } = new(
        ProviderId.DeepSeek,
        "deepseek-v4-flash",
        new Uri("https://api.deepseek.com/chat/completions"),
        TimeSpan.FromSeconds(15),
        TimeSpan.FromSeconds(45),
        4_096);

    public static ProviderProfile For(ProviderId provider) => provider switch
    {
        ProviderId.Qwen => Qwen,
        ProviderId.DeepSeek => DeepSeek,
        _ => throw new ArgumentOutOfRangeException(nameof(provider), provider, null),
    };
}

public sealed record ProviderDiagnostics(
    ProviderId Provider,
    string Model,
    int HttpStatus,
    string? RequestId,
    int ResponseBytes);

public sealed record ProviderValidationResult(ProviderDiagnostics Diagnostics);

public sealed record ProviderTranslationResult(
    string Text,
    ProviderDiagnostics Diagnostics);

public sealed record SanitizedProviderDiagnostics(
    ProviderId Provider,
    ProviderErrorCategory Category,
    int? HttpStatus,
    string? RequestId,
    string AppVersion);

public interface IProviderHttpTransport
{
    ValueTask<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken = default);
}

public interface ITranslationProvider
{
    ProviderId Provider { get; }

    ProviderProfile Profile { get; }

    ValueTask<ProviderValidationResult> ValidateCredentialAsync(
        string credential,
        CancellationToken cancellationToken = default);

    ValueTask<ProviderTranslationResult> TranslateAsync(
        string sourceText,
        string credential,
        CancellationToken cancellationToken = default);
}

public sealed class ProviderRequestException : Exception
{
    public ProviderRequestException(
        ProviderId provider,
        ProviderErrorCategory category,
        int? httpStatus = null,
        string? requestId = null,
        Exception? innerException = null)
        : base($"{provider.DisplayName()} request failed: {category}.", innerException)
    {
        Provider = provider;
        Category = category;
        HttpStatus = httpStatus;
        RequestId = requestId;
    }

    public ProviderId Provider { get; }

    public ProviderErrorCategory Category { get; }

    public int? HttpStatus { get; }

    public string? RequestId { get; }

    public SanitizedProviderDiagnostics ToSanitizedDiagnostics(string appVersion) => new(
        Provider,
        Category,
        HttpStatus,
        RequestId,
        appVersion);
}

public sealed class HttpClientProviderTransport : IProviderHttpTransport, IDisposable
{
    private readonly HttpClient _client;
    private readonly bool _ownsClient;

    public HttpClientProviderTransport()
        : this(CreateClient(), ownsClient: true)
    {
    }

    public HttpClientProviderTransport(HttpClient client)
        : this(client, ownsClient: false)
    {
    }

    private HttpClientProviderTransport(HttpClient client, bool ownsClient)
    {
        _client = client ?? throw new ArgumentNullException(nameof(client));
        _ownsClient = ownsClient;
    }

    public async ValueTask<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken = default) =>
        await _client.SendAsync(
            request,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken).ConfigureAwait(false);

    public void Dispose()
    {
        if (_ownsClient)
        {
            _client.Dispose();
        }
    }

    private static HttpClient CreateClient()
    {
        var client = new HttpClient
        {
            Timeout = Timeout.InfiniteTimeSpan,
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("EPUBTranslator-Windows/0.1");
        return client;
    }
}

public sealed class LazyProviderHttpTransport : IProviderHttpTransport, IDisposable
{
    private readonly Lazy<HttpClientProviderTransport> _inner = new(
        static () => new HttpClientProviderTransport(),
        LazyThreadSafetyMode.ExecutionAndPublication);

    public ValueTask<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken = default) =>
        _inner.Value.SendAsync(request, cancellationToken);

    public void Dispose()
    {
        if (_inner.IsValueCreated)
        {
            _inner.Value.Dispose();
        }
    }
}

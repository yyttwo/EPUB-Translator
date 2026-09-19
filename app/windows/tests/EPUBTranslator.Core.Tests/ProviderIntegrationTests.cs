using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace EPUBTranslator.Core.Tests;

[TestClass]
public sealed class ProviderIntegrationTests
{
    private const string QwenCredential = "FAKE_QWEN_CREDENTIAL";
    private const string DeepSeekCredential = "FAKE_DEEPSEEK_CREDENTIAL";

    [TestMethod]
    [TestCategory("QwenMock")]
    public async Task Qwen_Success_UsesApprovedProfileAndParsesChineseResult()
    {
        var transport = SuccessTransport("安全边际很重要。", "qwen-request-1");
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, transport);

        var result = await provider.TranslateAsync(
            OpenAiCompatibleTranslationProvider.TranslationSmokeSourceText,
            QwenCredential);

        Assert.AreEqual("安全边际很重要。", result.Text);
        Assert.AreEqual("qwen3.7-plus", result.Diagnostics.Model);
        Assert.AreEqual(200, result.Diagnostics.HttpStatus);
        Assert.AreEqual("qwen-request-1", result.Diagnostics.RequestId);
        Assert.AreEqual(ProviderProfiles.Qwen.Endpoint, transport.RequestUri);
        Assert.AreEqual(QwenCredential, transport.AuthorizationParameter);

        using var request = JsonDocument.Parse(transport.RequestBody!);
        Assert.AreEqual("qwen3.7-plus", request.RootElement.GetProperty("model").GetString());
        Assert.IsFalse(request.RootElement.GetProperty("enable_thinking").GetBoolean());
        Assert.AreEqual("json_schema", request.RootElement.GetProperty("response_format").GetProperty("type").GetString());
        Assert.AreEqual(
            OpenAiCompatibleTranslationProvider.TranslationSmokeSourceText,
            request.RootElement.GetProperty("messages")[1].GetProperty("content").GetString());
    }

    [TestMethod]
    [TestCategory("DeepSeekMock")]
    public async Task DeepSeek_Success_UsesApprovedProfileAndParsesChineseResult()
    {
        var transport = SuccessTransport("安全边际至关重要。", "deepseek-request-1");
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.DeepSeek, transport);

        var result = await provider.TranslateAsync(
            OpenAiCompatibleTranslationProvider.TranslationSmokeSourceText,
            DeepSeekCredential);

        Assert.AreEqual("安全边际至关重要。", result.Text);
        Assert.AreEqual("deepseek-v4-flash", result.Diagnostics.Model);
        Assert.AreEqual(ProviderProfiles.DeepSeek.Endpoint, transport.RequestUri);
        Assert.AreEqual(DeepSeekCredential, transport.AuthorizationParameter);

        using var request = JsonDocument.Parse(transport.RequestBody!);
        Assert.AreEqual("deepseek-v4-flash", request.RootElement.GetProperty("model").GetString());
        Assert.AreEqual("disabled", request.RootElement.GetProperty("thinking").GetProperty("type").GetString());
        Assert.AreEqual(4_096, request.RootElement.GetProperty("max_tokens").GetInt32());
        Assert.AreEqual("json_object", request.RootElement.GetProperty("response_format").GetProperty("type").GetString());
    }

    [TestMethod]
    [TestCategory("ErrorMapping")]
    public async Task HttpFailures_MapToDistinctSafeCategories()
    {
        var cases = new[]
        {
            (HttpStatusCode.Unauthorized, ProviderErrorCategory.Authentication),
            (HttpStatusCode.Forbidden, ProviderErrorCategory.Permission),
            ((HttpStatusCode)429, ProviderErrorCategory.RateLimit),
            (HttpStatusCode.InternalServerError, ProviderErrorCategory.ProviderService),
            (HttpStatusCode.ServiceUnavailable, ProviderErrorCategory.ProviderService),
        };

        foreach (var (status, expected) in cases)
        {
            var transport = new ScriptedTransport((_, _) =>
            {
                var response = new HttpResponseMessage(status)
                {
                    Content = new StringContent("PRIVATE_PROVIDER_BODY_MUST_NOT_SURFACE"),
                };
                response.Headers.TryAddWithoutValidation("x-request-id", "safe-request-2");
                return ValueTask.FromResult(response);
            });
            var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, transport);

            var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
                await provider.ValidateCredentialAsync(QwenCredential));

            Assert.AreEqual(expected, exception.Category);
            Assert.AreEqual((int)status, exception.HttpStatus);
            Assert.AreEqual("safe-request-2", exception.RequestId);
            var userError = UserFacingErrors.ProviderRequestFailed(exception);
            var exposed = $"{userError.Title} {userError.Message} {userError.RecoveryHint} {userError.TechnicalCode}";
            Assert.IsFalse(exposed.Contains(QwenCredential, StringComparison.Ordinal));
            Assert.IsFalse(exposed.Contains("PRIVATE_PROVIDER_BODY", StringComparison.Ordinal));
        }
    }

    [TestMethod]
    [TestCategory("Timeout")]
    public async Task ProviderTimeout_StopsWaitingAndMapsTimeout()
    {
        var profile = ProviderProfiles.Qwen with
        {
            ValidationTimeout = TimeSpan.FromMilliseconds(40),
        };
        var provider = new OpenAiCompatibleTranslationProvider(profile, BlockingTransport());

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await provider.ValidateCredentialAsync(QwenCredential));

        Assert.AreEqual(ProviderErrorCategory.Timeout, exception.Category);
    }

    [TestMethod]
    [TestCategory("Cancel")]
    public async Task UserCancellation_StopsWaitingAndMapsCancelled()
    {
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, BlockingTransport());
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(40));

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await provider.TranslateAsync("Short test.", QwenCredential, cancellation.Token));

        Assert.AreEqual(ProviderErrorCategory.Cancelled, exception.Category);
    }

    [TestMethod]
    [TestCategory("ErrorMapping")]
    public async Task NetworkInterruption_MapsNetworkFailure()
    {
        var transport = new ScriptedTransport((_, _) =>
            ValueTask.FromException<HttpResponseMessage>(new HttpRequestException("simulated interruption")));
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.DeepSeek, transport);

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await provider.ValidateCredentialAsync(DeepSeekCredential));

        Assert.AreEqual(ProviderErrorCategory.Network, exception.Category);
    }

    [TestMethod]
    [TestCategory("ErrorMapping")]
    public async Task CredentialWithCopiedPunctuation_IsRejectedBeforeTransport()
    {
        var transport = SuccessTransport("不应被调用。", "unexpected-request");
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, transport);

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await provider.ValidateCredentialAsync("FAKE_QWEN_CREDENTIAL，"));

        Assert.AreEqual(ProviderErrorCategory.InvalidCredentialFormat, exception.Category);
        Assert.AreEqual(0, transport.CallCount);
        Assert.AreEqual(
            "WIN_PROVIDER_CREDENTIAL_FORMAT",
            UserFacingErrors.ProviderRequestFailed(exception).TechnicalCode);
    }

    [TestMethod]
    [TestCategory("ErrorMapping")]
    public async Task EmptyResponse_MapsEmptyResponse()
    {
        var transport = new ScriptedTransport((_, _) => ValueTask.FromResult(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([]),
            }));
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, transport);

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await provider.ValidateCredentialAsync(QwenCredential));

        Assert.AreEqual(ProviderErrorCategory.EmptyResponse, exception.Category);
    }

    [TestMethod]
    [TestCategory("ErrorMapping")]
    public async Task MalformedResponse_MapsMalformedResponse()
    {
        var transport = new ScriptedTransport((_, _) => ValueTask.FromResult(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("{not-valid-json", Encoding.UTF8, "application/json"),
            }));
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.DeepSeek, transport);

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await provider.ValidateCredentialAsync(DeepSeekCredential));

        Assert.AreEqual(ProviderErrorCategory.MalformedResponse, exception.Category);
    }

    [TestMethod]
    [TestCategory("ErrorMapping")]
    public async Task TruncatedResponse_MapsOutputTruncated()
    {
        var transport = JsonResponseTransport(new
        {
            choices = new[]
            {
                new
                {
                    finish_reason = "length",
                    message = new { content = "{\"translation\":\"被截断\"}" },
                },
            },
        });
        var provider = OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, transport);

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await provider.ValidateCredentialAsync(QwenCredential));

        Assert.AreEqual(ProviderErrorCategory.OutputTruncated, exception.Category);
    }

    [TestMethod]
    [TestCategory("CredentialIsolation")]
    public async Task Coordinator_UsesOnlyTheSelectedProviderCredential()
    {
        var store = new RecordingCredentialStore(new Dictionary<ProviderId, string>
        {
            [ProviderId.Qwen] = QwenCredential,
            [ProviderId.DeepSeek] = DeepSeekCredential,
        });
        var qwenTransport = SuccessTransport("验证成功。", "qwen-isolated");
        var deepSeekTransport = SuccessTransport("验证成功。", "deepseek-isolated");
        var coordinator = new ProviderCoordinator(
            store,
            new ITranslationProvider[]
            {
                OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, qwenTransport),
                OpenAiCompatibleTranslationProvider.Create(ProviderId.DeepSeek, deepSeekTransport),
            });

        await coordinator.ValidateCredentialAsync(ProviderId.Qwen);
        Assert.AreEqual(QwenCredential, qwenTransport.AuthorizationParameter);
        Assert.IsNull(deepSeekTransport.AuthorizationParameter);
        CollectionAssert.AreEqual(new[] { ProviderId.Qwen }, store.Reads.ToArray());

        store.Reads.Clear();
        await coordinator.ValidateCredentialAsync(ProviderId.DeepSeek);
        Assert.AreEqual(DeepSeekCredential, deepSeekTransport.AuthorizationParameter);
        CollectionAssert.AreEqual(new[] { ProviderId.DeepSeek }, store.Reads.ToArray());
    }

    [TestMethod]
    [TestCategory("CredentialIsolation")]
    public async Task Coordinator_DoesNotFallbackToTheOtherProvider()
    {
        var store = new RecordingCredentialStore(new Dictionary<ProviderId, string>
        {
            [ProviderId.Qwen] = QwenCredential,
            [ProviderId.DeepSeek] = DeepSeekCredential,
        });
        var qwenTransport = new ScriptedTransport((_, _) => ValueTask.FromResult(
            new HttpResponseMessage(HttpStatusCode.ServiceUnavailable)
            {
                Content = new StringContent("simulated provider failure"),
            }));
        var deepSeekTransport = SuccessTransport("不应被调用。", "unexpected-fallback");
        var coordinator = new ProviderCoordinator(
            store,
            new ITranslationProvider[]
            {
                OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, qwenTransport),
                OpenAiCompatibleTranslationProvider.Create(ProviderId.DeepSeek, deepSeekTransport),
            });

        var exception = await Assert.ThrowsExactlyAsync<ProviderRequestException>(async () =>
            await coordinator.ValidateCredentialAsync(ProviderId.Qwen));

        Assert.AreEqual(ProviderErrorCategory.ProviderService, exception.Category);
        Assert.AreEqual(1, qwenTransport.CallCount);
        Assert.AreEqual(0, deepSeekTransport.CallCount);
        CollectionAssert.AreEqual(new[] { ProviderId.Qwen }, store.Reads.ToArray());
    }

    [TestMethod]
    [TestCategory("ErrorMapping")]
    public void SanitizedDiagnostics_ContainNoCredentialOrRawBody()
    {
        var exception = new ProviderRequestException(
            ProviderId.Qwen,
            ProviderErrorCategory.Authentication,
            401,
            "safe-request-3",
            new InvalidOperationException("PRIVATE_INTERNAL_DETAIL"));

        var diagnostics = exception.ToSanitizedDiagnostics("0.1.0");
        var serialized = JsonSerializer.Serialize(diagnostics);

        Assert.IsFalse(serialized.Contains(QwenCredential, StringComparison.Ordinal));
        Assert.IsFalse(serialized.Contains("PRIVATE_INTERNAL_DETAIL", StringComparison.Ordinal));
        Assert.AreEqual("safe-request-3", diagnostics.RequestId);
        Assert.AreEqual(401, diagnostics.HttpStatus);
    }

    private static ScriptedTransport SuccessTransport(string translation, string requestId)
    {
        var transport = JsonResponseTransport(new
        {
            choices = new[]
            {
                new
                {
                    finish_reason = "stop",
                    message = new
                    {
                        content = JsonSerializer.Serialize(new { translation }),
                    },
                },
            },
        });
        transport.ResponseRequestId = requestId;
        return transport;
    }

    private static ScriptedTransport JsonResponseTransport(object payload) =>
        new((_, _) => ValueTask.FromResult(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(payload),
                    Encoding.UTF8,
                    "application/json"),
            }));

    private static ScriptedTransport BlockingTransport() =>
        new(async (_, cancellationToken) =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            throw new AssertFailedException("The blocking transport must be cancelled.");
        });

    private sealed class ScriptedTransport : IProviderHttpTransport
    {
        private readonly Func<HttpRequestMessage, CancellationToken, ValueTask<HttpResponseMessage>> _handler;

        public ScriptedTransport(
            Func<HttpRequestMessage, CancellationToken, ValueTask<HttpResponseMessage>> handler)
        {
            _handler = handler;
        }

        public int CallCount { get; private set; }

        public Uri? RequestUri { get; private set; }

        public string? AuthorizationParameter { get; private set; }

        public string? RequestBody { get; private set; }

        public string? ResponseRequestId { get; set; }

        public async ValueTask<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken = default)
        {
            CallCount++;
            RequestUri = request.RequestUri;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            RequestBody = request.Content is null
                ? null
                : await request.Content.ReadAsStringAsync(cancellationToken);
            var response = await _handler(request, cancellationToken);
            if (!string.IsNullOrWhiteSpace(ResponseRequestId))
            {
                response.Headers.TryAddWithoutValidation("x-request-id", ResponseRequestId);
            }

            return response;
        }
    }

    private sealed class RecordingCredentialStore : ICredentialStore
    {
        private readonly Dictionary<ProviderId, string> _credentials;

        public RecordingCredentialStore(Dictionary<ProviderId, string> credentials)
        {
            _credentials = credentials;
        }

        public List<ProviderId> Reads { get; } = [];

        public ValueTask SaveAsync(
            ProviderId provider,
            string secret,
            CancellationToken cancellationToken = default)
        {
            _credentials.Add(provider, secret);
            return ValueTask.CompletedTask;
        }

        public ValueTask<string?> ReadAsync(
            ProviderId provider,
            CancellationToken cancellationToken = default)
        {
            Reads.Add(provider);
            return ValueTask.FromResult(_credentials.GetValueOrDefault(provider));
        }

        public ValueTask ReplaceAsync(
            ProviderId provider,
            string secret,
            CancellationToken cancellationToken = default)
        {
            _credentials[provider] = secret;
            return ValueTask.CompletedTask;
        }

        public ValueTask<bool> DeleteAsync(
            ProviderId provider,
            CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(_credentials.Remove(provider));

        public ValueTask<bool> ExistsAsync(
            ProviderId provider,
            CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(_credentials.ContainsKey(provider));
    }
}

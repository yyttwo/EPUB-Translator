using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace EPUBTranslator.Core;

public sealed class OpenAiCompatibleTranslationProvider : ITranslationProvider
{
    public const string ValidationSourceText = "The reading room is quiet.";
    public const string TranslationSmokeSourceText = "The margin of safety matters.";

    private const int MaximumResponseBytes = 1_048_576;
    private const string SystemPrompt =
        "Translate the supplied English text into Simplified Chinese. " +
        "Return exactly one JSON object with a non-empty string field named translation. " +
        "Do not add commentary or markdown.";

    private readonly IProviderHttpTransport _transport;

    public OpenAiCompatibleTranslationProvider(
        ProviderProfile profile,
        IProviderHttpTransport transport)
    {
        Profile = profile ?? throw new ArgumentNullException(nameof(profile));
        _transport = transport ?? throw new ArgumentNullException(nameof(transport));
        ValidateEndpoint(profile);
    }

    public ProviderId Provider => Profile.Provider;

    public ProviderProfile Profile { get; }

    public static OpenAiCompatibleTranslationProvider Create(
        ProviderId provider,
        IProviderHttpTransport transport) =>
        new(ProviderProfiles.For(provider), transport);

    public async ValueTask<ProviderValidationResult> ValidateCredentialAsync(
        string credential,
        CancellationToken cancellationToken = default)
    {
        var result = await SendAsync(
            ValidationSourceText,
            credential,
            Profile.ValidationTimeout,
            cancellationToken).ConfigureAwait(false);
        return new ProviderValidationResult(result.Diagnostics);
    }

    public ValueTask<ProviderTranslationResult> TranslateAsync(
        string sourceText,
        string credential,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(sourceText);
        return SendAsync(
            sourceText,
            credential,
            Profile.TranslationTimeout,
            cancellationToken);
    }

    private async ValueTask<ProviderTranslationResult> SendAsync(
        string sourceText,
        string credential,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var cleanCredential = ValidateCredential(credential);
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);

        try
        {
            using var request = BuildRequest(sourceText, cleanCredential);
            using var response = await _transport.SendAsync(request, timeoutSource.Token).ConfigureAwait(false);
            var requestId = SafeRequestId(response);
            if (response.Content.Headers.ContentLength > MaximumResponseBytes)
            {
                throw Failure(ProviderErrorCategory.MalformedResponse, response.StatusCode, requestId);
            }

            var body = await response.Content.ReadAsByteArrayAsync(timeoutSource.Token).ConfigureAwait(false);
            if (body.Length > MaximumResponseBytes)
            {
                throw Failure(ProviderErrorCategory.MalformedResponse, response.StatusCode, requestId);
            }

            if (!response.IsSuccessStatusCode)
            {
                throw Failure(MapStatus(response.StatusCode), response.StatusCode, requestId);
            }

            var translation = ParseTranslation(body);
            return new ProviderTranslationResult(
                translation,
                new ProviderDiagnostics(
                    Provider,
                    Profile.Model,
                    (int)response.StatusCode,
                    requestId,
                    body.Length));
        }
        catch (ProviderRequestException)
        {
            throw;
        }
        catch (OperationCanceledException exception) when (cancellationToken.IsCancellationRequested)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.Cancelled,
                innerException: exception);
        }
        catch (OperationCanceledException exception)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.Timeout,
                innerException: exception);
        }
        catch (HttpRequestException exception)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.Network,
                innerException: exception);
        }
        catch (IOException exception)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.Network,
                innerException: exception);
        }
        catch (FormatException exception)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.InvalidCredentialFormat,
                innerException: exception);
        }
        finally
        {
            cleanCredential = string.Empty;
        }
    }

    private HttpRequestMessage BuildRequest(string sourceText, string credential)
    {
        var payload = new Dictionary<string, object?>
        {
            ["model"] = Profile.Model,
            ["messages"] = new object[]
            {
                new Dictionary<string, string>
                {
                    ["role"] = "system",
                    ["content"] = SystemPrompt,
                },
                new Dictionary<string, string>
                {
                    ["role"] = "user",
                    ["content"] = sourceText,
                },
            },
            ["response_format"] = ResponseFormat(),
            ["temperature"] = 0.1,
            ["stream"] = false,
        };

        if (Provider == ProviderId.Qwen)
        {
            payload["enable_thinking"] = false;
        }
        else
        {
            payload["thinking"] = new Dictionary<string, string> { ["type"] = "disabled" };
            payload["max_tokens"] = Profile.MaximumOutputTokens;
        }

        var body = JsonSerializer.Serialize(payload);
        var request = new HttpRequestMessage(HttpMethod.Post, Profile.Endpoint)
        {
            Content = new StringContent(body, Encoding.UTF8, "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential);
        return request;
    }

    private object ResponseFormat()
    {
        if (Provider == ProviderId.DeepSeek)
        {
            return new Dictionary<string, string> { ["type"] = "json_object" };
        }

        return new Dictionary<string, object>
        {
            ["type"] = "json_schema",
            ["json_schema"] = new Dictionary<string, object>
            {
                ["name"] = "epub_translation_response",
                ["strict"] = true,
                ["schema"] = new Dictionary<string, object>
                {
                    ["type"] = "object",
                    ["properties"] = new Dictionary<string, object>
                    {
                        ["translation"] = new Dictionary<string, string> { ["type"] = "string" },
                    },
                    ["required"] = new[] { "translation" },
                    ["additionalProperties"] = false,
                },
            },
        };
    }

    private string ParseTranslation(byte[] body)
    {
        if (body.Length == 0)
        {
            throw Failure(ProviderErrorCategory.EmptyResponse);
        }

        try
        {
            using var envelope = JsonDocument.Parse(body);
            var choices = envelope.RootElement.GetProperty("choices");
            if (choices.GetArrayLength() == 0)
            {
                throw Failure(ProviderErrorCategory.MalformedResponse);
            }

            var first = choices[0];
            if (first.TryGetProperty("finish_reason", out var finishReason) &&
                string.Equals(finishReason.GetString(), "length", StringComparison.OrdinalIgnoreCase))
            {
                throw Failure(ProviderErrorCategory.OutputTruncated);
            }

            var content = first.GetProperty("message").GetProperty("content").GetString();
            if (string.IsNullOrWhiteSpace(content))
            {
                throw Failure(ProviderErrorCategory.EmptyResponse);
            }

            var translation = ParseContent(content);
            if (!ContainsChinese(translation))
            {
                throw Failure(ProviderErrorCategory.MalformedResponse);
            }

            return translation;
        }
        catch (ProviderRequestException)
        {
            throw;
        }
        catch (JsonException exception)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.MalformedResponse,
                innerException: exception);
        }
        catch (InvalidOperationException exception)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.MalformedResponse,
                innerException: exception);
        }
        catch (KeyNotFoundException exception)
        {
            throw new ProviderRequestException(
                Provider,
                ProviderErrorCategory.MalformedResponse,
                innerException: exception);
        }
    }

    private string ParseContent(string content)
    {
        var candidate = StripMarkdownFence(content.Trim());
        try
        {
            using var document = JsonDocument.Parse(candidate);
            foreach (var name in new[] { "translation", "translated_text", "translatedText", "text" })
            {
                if (document.RootElement.TryGetProperty(name, out var value) &&
                    value.ValueKind == JsonValueKind.String)
                {
                    var translation = value.GetString()?.Trim();
                    if (!string.IsNullOrWhiteSpace(translation))
                    {
                        return translation;
                    }
                }
            }

            throw Failure(ProviderErrorCategory.MalformedResponse);
        }
        catch (JsonException)
        {
            if (ContainsChinese(candidate) && !candidate.StartsWith('{') && !candidate.EndsWith('}'))
            {
                return candidate;
            }

            throw Failure(ProviderErrorCategory.MalformedResponse);
        }
    }

    private static string StripMarkdownFence(string content)
    {
        if (!content.StartsWith("```", StringComparison.Ordinal))
        {
            return content;
        }

        var lines = content.Split('\n');
        if (lines.Length < 3 || !lines[^1].Trim().Equals("```", StringComparison.Ordinal))
        {
            return content;
        }

        return string.Join('\n', lines.Skip(1).SkipLast(1)).Trim();
    }

    private static bool ContainsChinese(string value) =>
        value.EnumerateRunes().Any(rune => rune.Value is >= 0x3400 and <= 0x9FFF);

    private string ValidateCredential(string credential)
    {
        var value = credential?.Trim() ?? string.Empty;
        if (value.Length == 0)
        {
            throw Failure(ProviderErrorCategory.MissingCredential);
        }

        if (value.Length < 8 || value.Any(character =>
                !(char.IsAsciiLetterOrDigit(character) ||
                  character is '-' or '.' or '_' or '~' or '+' or '/' or '=')))
        {
            throw Failure(ProviderErrorCategory.InvalidCredentialFormat);
        }

        return value;
    }

    private ProviderRequestException Failure(
        ProviderErrorCategory category,
        HttpStatusCode? status = null,
        string? requestId = null) =>
        new(Provider, category, status is null ? null : (int)status, requestId);

    private static ProviderErrorCategory MapStatus(HttpStatusCode status) => (int)status switch
    {
        401 => ProviderErrorCategory.Authentication,
        403 => ProviderErrorCategory.Permission,
        429 => ProviderErrorCategory.RateLimit,
        >= 500 and <= 599 => ProviderErrorCategory.ProviderService,
        _ => ProviderErrorCategory.ProviderService,
    };

    private static string? SafeRequestId(HttpResponseMessage response)
    {
        if (!TryHeader(response, "x-request-id", out var value) &&
            !TryHeader(response, "request-id", out value))
        {
            return null;
        }

        var safe = new string(value
            .Where(character => char.IsLetterOrDigit(character) || character is '-' or '_' or '.' or ':')
            .Take(128)
            .ToArray());
        return string.IsNullOrWhiteSpace(safe) ? null : safe;
    }

    private static bool TryHeader(HttpResponseMessage response, string name, out string value)
    {
        value = string.Empty;
        if (!response.Headers.TryGetValues(name, out var values))
        {
            return false;
        }

        value = values.FirstOrDefault() ?? string.Empty;
        return !string.IsNullOrWhiteSpace(value);
    }

    private static void ValidateEndpoint(ProviderProfile profile)
    {
        var valid = profile.Endpoint.Scheme == Uri.UriSchemeHttps &&
            profile.Endpoint.UserInfo.Length == 0 &&
            string.IsNullOrEmpty(profile.Endpoint.Query) &&
            string.IsNullOrEmpty(profile.Endpoint.Fragment) &&
            (profile.Provider switch
            {
                ProviderId.Qwen =>
                    profile.Endpoint.Host.Equals("dashscope.aliyuncs.com", StringComparison.OrdinalIgnoreCase) &&
                    profile.Endpoint.AbsolutePath == "/compatible-mode/v1/chat/completions",
                ProviderId.DeepSeek =>
                    profile.Endpoint.Host.Equals("api.deepseek.com", StringComparison.OrdinalIgnoreCase) &&
                    profile.Endpoint.AbsolutePath == "/chat/completions",
                _ => false,
            });

        if (!valid)
        {
            throw new ArgumentException("The provider endpoint does not match the approved profile.", nameof(profile));
        }
    }
}

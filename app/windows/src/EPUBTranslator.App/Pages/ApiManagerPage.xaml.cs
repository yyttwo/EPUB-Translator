using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using EPUBTranslator.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace EPUBTranslator.App.Pages;

[SuppressMessage(
    "Design",
    "CA1001:Types that own disposable fields should be disposable",
    Justification = "WinUI owns Page lifetime; the cancellation source is cancelled and disposed from Unloaded and after every operation.")]
public sealed partial class ApiManagerPage : Page
{
    private CancellationTokenSource? _operationCancellation;
    private ProviderId? _busyProvider;

    public ApiManagerPage()
    {
        InitializeComponent();
        Loaded += Page_Loaded;
        Unloaded += Page_Unloaded;
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        await RefreshAllAsync();
    }

    private void Page_Unloaded(object sender, RoutedEventArgs e)
    {
        _operationCancellation?.Cancel();
        _operationCancellation?.Dispose();
        _operationCancellation = null;
        _busyProvider = null;
    }

    private async void AddCredential_Click(object sender, RoutedEventArgs e)
    {
        await SaveCredentialAsync(GetProvider(sender), replace: false);
    }

    private async void ReplaceCredential_Click(object sender, RoutedEventArgs e)
    {
        await SaveCredentialAsync(GetProvider(sender), replace: true);
    }

    private async void DeleteCredential_Click(object sender, RoutedEventArgs e)
    {
        var provider = GetProvider(sender);
        var confirmation = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = $"删除 {provider.DisplayName()} API Key？",
            Content = "删除后，该服务会显示为未配置。",
            PrimaryButtonText = "删除",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close,
        };

        if (await confirmation.ShowAsync() != ContentDialogResult.Primary)
        {
            return;
        }

        try
        {
            await App.Services.CredentialStore.DeleteAsync(provider);
            App.Services.ProviderSessionState.Invalidate(provider);
            ClearPassword(provider);
            GetSmokeResultText(provider).Text = "尚未运行翻译测试。";
            await RefreshProviderAsync(provider);
            ShowStatus("API Key 已删除", $"{provider.DisplayName()} 已恢复为未配置。", InfoBarSeverity.Success);
        }
        catch (Exception exception)
        {
            ShowError(UserFacingErrors.FromException(exception, "credential"));
        }
    }

    private async void ValidateCredential_Click(object sender, RoutedEventArgs e)
    {
        var provider = GetProvider(sender);
        if (!await BeginProviderOperationAsync(provider))
        {
            return;
        }

        try
        {
            App.Services.ProviderSessionState.RecordRequest(provider);
            var result = await App.Services.ProviderCoordinator.ValidateCredentialAsync(
                provider,
                _operationCancellation!.Token);
            App.Services.ProviderSessionState.MarkValidated(provider);
            ShowStatus(
                $"{provider.DisplayName()} 验证成功",
                BuildSuccessDiagnostics(result.Diagnostics),
                InfoBarSeverity.Success);
        }
        catch (ProviderRequestException exception)
        {
            if (exception.Category is ProviderErrorCategory.Authentication or
                ProviderErrorCategory.Permission or
                ProviderErrorCategory.InvalidCredentialFormat or
                ProviderErrorCategory.MissingCredential)
            {
                App.Services.ProviderSessionState.Invalidate(provider);
            }

            ShowProviderError(exception);
        }
        catch (Exception exception)
        {
            ShowError(UserFacingErrors.FromException(exception, "provider"));
        }
        finally
        {
            await EndProviderOperationAsync(provider);
        }
    }

    private async void TranslationSmoke_Click(object sender, RoutedEventArgs e)
    {
        var provider = GetProvider(sender);
        if (!App.Services.ProviderSessionState.IsValidated(provider))
        {
            ShowStatus(
                "请先验证 API Key",
                $"{provider.DisplayName()} 必须在本次会话验证成功后才能运行翻译测试。",
                InfoBarSeverity.Warning);
            return;
        }

        if (!await BeginProviderOperationAsync(provider))
        {
            return;
        }

        try
        {
            App.Services.ProviderSessionState.RecordRequest(provider);
            var result = await App.Services.ProviderCoordinator.TranslateAsync(
                provider,
                OpenAiCompatibleTranslationProvider.TranslationSmokeSourceText,
                _operationCancellation!.Token);
            GetSmokeResultText(provider).Text =
                $"原文：{OpenAiCompatibleTranslationProvider.TranslationSmokeSourceText}\n译文：{result.Text}";
            ShowStatus(
                $"{provider.DisplayName()} 翻译测试成功",
                BuildSuccessDiagnostics(result.Diagnostics),
                InfoBarSeverity.Success);
        }
        catch (ProviderRequestException exception)
        {
            if (exception.Category is ProviderErrorCategory.Authentication or
                ProviderErrorCategory.Permission or
                ProviderErrorCategory.InvalidCredentialFormat or
                ProviderErrorCategory.MissingCredential)
            {
                App.Services.ProviderSessionState.Invalidate(provider);
            }

            ShowProviderError(exception);
        }
        catch (Exception exception)
        {
            ShowError(UserFacingErrors.FromException(exception, "provider"));
        }
        finally
        {
            await EndProviderOperationAsync(provider);
        }
    }

    private void CancelProviderOperation_Click(object sender, RoutedEventArgs e)
    {
        var provider = GetProvider(sender);
        if (_busyProvider == provider)
        {
            _operationCancellation?.Cancel();
        }
    }

    private async Task SaveCredentialAsync(ProviderId provider, bool replace)
    {
        var passwordBox = GetPasswordBox(provider);
        var secret = passwordBox.Password;
        if (string.IsNullOrWhiteSpace(secret))
        {
            ShowStatus("请输入 API Key", "API Key 不能为空。", InfoBarSeverity.Warning);
            return;
        }

        try
        {
            if (replace)
            {
                await App.Services.CredentialStore.ReplaceAsync(provider, secret);
            }
            else
            {
                await App.Services.CredentialStore.SaveAsync(provider, secret);
            }

            App.Services.ProviderSessionState.Invalidate(provider);
            passwordBox.Password = string.Empty;
            secret = string.Empty;
            GetSmokeResultText(provider).Text = "尚未运行翻译测试。";
            await RefreshProviderAsync(provider);
            ShowStatus(
                replace ? "API Key 已更换" : "API Key 已保存",
                $"{provider.DisplayName()} 凭据已由 Windows 凭据管理器保存；请点击验证。",
                InfoBarSeverity.Success);
        }
        catch (Exception exception)
        {
            passwordBox.Password = string.Empty;
            secret = string.Empty;
            ShowError(UserFacingErrors.FromException(exception, "credential"));
        }
    }

    private async Task<bool> BeginProviderOperationAsync(ProviderId provider)
    {
        if (_operationCancellation is not null)
        {
            ShowStatus("已有请求正在运行", "请等待当前请求完成，或先取消。", InfoBarSeverity.Warning);
            return false;
        }

        if (!await App.Services.CredentialStore.ExistsAsync(provider))
        {
            ShowError(UserFacingErrors.ProviderNotConfigured());
            return false;
        }

        _busyProvider = provider;
        _operationCancellation = new CancellationTokenSource();
        await RefreshAllAsync();
        return true;
    }

    private async Task EndProviderOperationAsync(ProviderId provider)
    {
        _operationCancellation?.Dispose();
        _operationCancellation = null;
        _busyProvider = null;
        await RefreshProviderAsync(provider);
    }

    private async Task RefreshAllAsync()
    {
        try
        {
            await RefreshProviderAsync(ProviderId.Qwen);
            await RefreshProviderAsync(ProviderId.DeepSeek);
        }
        catch (Exception exception)
        {
            ShowError(UserFacingErrors.FromException(exception, "credential"));
        }
    }

    private async Task RefreshProviderAsync(ProviderId provider)
    {
        var configured = await App.Services.CredentialStore.ExistsAsync(provider);
        var validated = App.Services.ProviderSessionState.IsValidated(provider);
        var count = App.Services.ProviderSessionState.RequestCount(provider);
        var busy = _operationCancellation is not null;

        GetStatusText(provider).Text = configured
            ? validated
                ? $"验证成功 · 本次会话请求 {count}"
                : $"已配置，待验证 · 本次会话请求 {count}"
            : "未配置";
        GetAddButton(provider).IsEnabled = !configured && !busy;
        GetReplaceButton(provider).IsEnabled = configured && !busy;
        GetDeleteButton(provider).IsEnabled = configured && !busy;
        GetValidateButton(provider).IsEnabled = configured && !busy;
        GetSmokeButton(provider).IsEnabled = configured && validated && !busy;
        GetCancelButton(provider).IsEnabled = _busyProvider == provider;
    }

    private static string BuildSuccessDiagnostics(ProviderDiagnostics diagnostics)
    {
        var requestId = string.IsNullOrWhiteSpace(diagnostics.RequestId)
            ? "无"
            : diagnostics.RequestId;
        return $"模型 {diagnostics.Model} · HTTP {diagnostics.HttpStatus} · Request ID {requestId}";
    }

    private void ShowProviderError(ProviderRequestException exception)
    {
        var error = UserFacingErrors.ProviderRequestFailed(exception);
        var diagnostics = exception.ToSanitizedDiagnostics("0.1.0");
        var requestId = string.IsNullOrWhiteSpace(diagnostics.RequestId) ? "无" : diagnostics.RequestId;
        var httpStatus = diagnostics.HttpStatus?.ToString(CultureInfo.InvariantCulture) ?? "无";
        ShowStatus(
            error.Title,
            $"{error.Message} {error.RecoveryHint} 诊断：{diagnostics.Provider} / {diagnostics.Category} / HTTP {httpStatus} / Request ID {requestId}",
            exception.Category == ProviderErrorCategory.Cancelled
                ? InfoBarSeverity.Informational
                : InfoBarSeverity.Error);
    }

    private static ProviderId GetProvider(object sender)
    {
        if (sender is Button { Tag: string tag } && Enum.TryParse<ProviderId>(tag, out var provider))
        {
            return provider;
        }

        throw new InvalidOperationException("The credential action has no valid Provider ID.");
    }

    private PasswordBox GetPasswordBox(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenPasswordBox : DeepSeekPasswordBox;

    private TextBlock GetStatusText(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenStatusText : DeepSeekStatusText;

    private TextBlock GetSmokeResultText(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenSmokeResultText : DeepSeekSmokeResultText;

    private Button GetAddButton(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenAddButton : DeepSeekAddButton;

    private Button GetReplaceButton(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenReplaceButton : DeepSeekReplaceButton;

    private Button GetDeleteButton(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenDeleteButton : DeepSeekDeleteButton;

    private Button GetValidateButton(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenValidateButton : DeepSeekValidateButton;

    private Button GetSmokeButton(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenSmokeButton : DeepSeekSmokeButton;

    private Button GetCancelButton(ProviderId provider) =>
        provider == ProviderId.Qwen ? QwenCancelButton : DeepSeekCancelButton;

    private void ClearPassword(ProviderId provider)
    {
        GetPasswordBox(provider).Password = string.Empty;
    }

    private void ShowError(UserFacingError error)
    {
        ShowStatus(error.Title, $"{error.Message} {error.RecoveryHint}", InfoBarSeverity.Error);
    }

    private void ShowStatus(string title, string message, InfoBarSeverity severity)
    {
        StatusInfoBar.Title = title;
        StatusInfoBar.Message = message;
        StatusInfoBar.Severity = severity;
        StatusInfoBar.IsOpen = true;
    }
}

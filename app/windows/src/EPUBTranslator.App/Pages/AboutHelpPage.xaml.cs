using EPUBTranslator.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace EPUBTranslator.App.Pages;

public sealed partial class AboutHelpPage : Page
{
    public AboutHelpPage()
    {
        InitializeComponent();
    }

    private async void Feedback_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (!await App.Services.ExternalLinkLauncher.LaunchAsync(SupportLinks.Feedback))
            {
                ShowFailure();
            }
        }
        catch
        {
            ShowFailure();
        }
    }

    private void ShowFailure()
    {
        StatusInfoBar.Title = "无法打开反馈页面";
        StatusInfoBar.Message = "请稍后重试，或手动访问 EPUB翻译 的 GitHub Issues 页面。";
        StatusInfoBar.Severity = InfoBarSeverity.Error;
        StatusInfoBar.IsOpen = true;
    }
}

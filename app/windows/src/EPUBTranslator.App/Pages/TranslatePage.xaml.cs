using EPUBTranslator.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace EPUBTranslator.App.Pages;

public sealed partial class TranslatePage : Page
{
    private BookSelection? _selection;

    public TranslatePage()
    {
        InitializeComponent();
    }

    private async void SelectEpub_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var selection = await App.Services.FileOpenPicker.PickEpubAsync();
            if (selection is null)
            {
                return;
            }

            _selection = selection;
            SelectedFileText.Text = selection.FileName;
            SelectedFileDetailsText.Text = $"{selection.HumanReadableSize} · EPUB";
            SaveSmokeCopyButton.IsEnabled = true;
            ShowStatus("已选择电子书", "文件已读取；Stage 2 不会翻译或上传整本内容。", InfoBarSeverity.Success);
        }
        catch (Exception exception)
        {
            ShowError(UserFacingErrors.FromException(exception, "open"));
        }
    }

    private async void SaveSmokeCopy_Click(object sender, RoutedEventArgs e)
    {
        if (_selection is null)
        {
            ShowError(UserFacingErrors.FileReadFailed());
            return;
        }

        try
        {
            var suggestedName = FilePathPolicy.SuggestedSmokeCopyName(_selection.FullPath);
            var destination = await App.Services.FileSavePicker.PickEpubDestinationAsync(suggestedName);
            if (destination is null)
            {
                return;
            }

            await App.Services.FileCopyService.CopyAsync(
                _selection.FullPath,
                destination,
                overwrite: true);
            ShowStatus("测试副本已保存", "保存权限与目标路径可用；原文件没有被覆盖。", InfoBarSeverity.Success);
        }
        catch (Exception exception)
        {
            ShowError(UserFacingErrors.FromException(exception, "save"));
        }
    }

    private void StartTranslation_Click(object sender, RoutedEventArgs e)
    {
        ShowStatus(
            "整本翻译尚未开放",
            "Stage 2 仅在“API 管理”页提供极短的 Provider 翻译测试。",
            InfoBarSeverity.Informational);
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

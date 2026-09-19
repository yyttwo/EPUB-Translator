using EPUBTranslator.Core;
using Microsoft.UI;
using Microsoft.Windows.Storage.Pickers;

namespace EPUBTranslator.Platform.Windows;

public sealed class WindowsFilePickerService(WindowId ownerWindowId) : IFileOpenPicker, IFileSavePicker
{
    public async ValueTask<BookSelection?> PickEpubAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var picker = new FileOpenPicker(ownerWindowId)
        {
            CommitButtonText = "选择 EPUB",
            SettingsIdentifier = "EPUBTranslator.OpenEpub",
        };
        picker.FileTypeFilter.Add(".epub");

        var result = await picker.PickSingleFileAsync();
        cancellationToken.ThrowIfCancellationRequested();
        if (result is null)
        {
            return null;
        }

        FilePathPolicy.EnsureEpub(result.Path);
        var file = new FileInfo(result.Path);
        if (!file.Exists)
        {
            throw new FileNotFoundException("The selected EPUB no longer exists.", result.Path);
        }

        return new BookSelection(file.FullName, file.Name, file.Length);
    }

    public async ValueTask<string?> PickEpubDestinationAsync(
        string suggestedFileName,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        FilePathPolicy.EnsureEpub(suggestedFileName);

        var picker = new FileSavePicker(ownerWindowId)
        {
            CommitButtonText = "保存测试副本",
            DefaultFileExtension = ".epub",
            SettingsIdentifier = "EPUBTranslator.SaveEpub",
            ShowOverwritePrompt = true,
            SuggestedFileName = Path.GetFileName(suggestedFileName),
        };
        picker.FileTypeChoices.Add("EPUB 电子书", new[] { ".epub" });

        var result = await picker.PickSaveFileAsync();
        cancellationToken.ThrowIfCancellationRequested();
        if (result is null)
        {
            return null;
        }

        FilePathPolicy.EnsureEpub(result.Path);
        return Path.GetFullPath(result.Path);
    }
}

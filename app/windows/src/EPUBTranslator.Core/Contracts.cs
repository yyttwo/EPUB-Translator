namespace EPUBTranslator.Core;

public interface ICredentialStore
{
    ValueTask SaveAsync(ProviderId provider, string secret, CancellationToken cancellationToken = default);

    ValueTask<string?> ReadAsync(ProviderId provider, CancellationToken cancellationToken = default);

    ValueTask ReplaceAsync(ProviderId provider, string secret, CancellationToken cancellationToken = default);

    ValueTask<bool> DeleteAsync(ProviderId provider, CancellationToken cancellationToken = default);

    ValueTask<bool> ExistsAsync(ProviderId provider, CancellationToken cancellationToken = default);
}

public interface IFileOpenPicker
{
    ValueTask<BookSelection?> PickEpubAsync(CancellationToken cancellationToken = default);
}

public interface IFileSavePicker
{
    ValueTask<string?> PickEpubDestinationAsync(
        string suggestedFileName,
        CancellationToken cancellationToken = default);
}

public interface IFileCopyService
{
    ValueTask CopyAsync(
        string sourcePath,
        string destinationPath,
        bool overwrite,
        CancellationToken cancellationToken = default);
}

public interface IAppDataPaths
{
    string RootDirectory { get; }

    string StateDirectory { get; }

    string CacheDirectory { get; }
}

public interface IExternalLinkLauncher
{
    ValueTask<bool> LaunchAsync(Uri uri, CancellationToken cancellationToken = default);
}

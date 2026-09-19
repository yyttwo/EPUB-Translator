using EPUBTranslator.Core;

namespace EPUBTranslator.Platform.Windows;

public sealed class WindowsFileCopyService : IFileCopyService
{
    public async ValueTask CopyAsync(
        string sourcePath,
        string destinationPath,
        bool overwrite,
        CancellationToken cancellationToken = default)
    {
        FilePathPolicy.EnsureEpub(sourcePath);
        FilePathPolicy.EnsureEpub(destinationPath);
        FilePathPolicy.EnsureDistinct(sourcePath, destinationPath);

        const int bufferSize = 128 * 1024;
        await using var source = new FileStream(
            sourcePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            bufferSize,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        await using var destination = new FileStream(
            destinationPath,
            overwrite ? FileMode.Create : FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            bufferSize,
            FileOptions.Asynchronous | FileOptions.SequentialScan);

        await source.CopyToAsync(destination, bufferSize, cancellationToken);
        await destination.FlushAsync(cancellationToken);
    }
}

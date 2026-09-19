namespace EPUBTranslator.Core;

public static class FilePathPolicy
{
    public static bool IsEpub(string path) =>
        string.Equals(Path.GetExtension(path), ".epub", StringComparison.OrdinalIgnoreCase);

    public static void EnsureEpub(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        if (!IsEpub(path))
        {
            throw new ArgumentException("Only .epub files are supported.", nameof(path));
        }
    }

    public static string SuggestedSmokeCopyName(string sourcePath)
    {
        EnsureEpub(sourcePath);
        var stem = Path.GetFileNameWithoutExtension(sourcePath);
        return $"{stem}-测试副本.epub";
    }

    public static bool ReferToSameWindowsPath(string firstPath, string secondPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(firstPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(secondPath);

        var first = Path.TrimEndingDirectorySeparator(Path.GetFullPath(firstPath));
        var second = Path.TrimEndingDirectorySeparator(Path.GetFullPath(secondPath));
        return string.Equals(first, second, StringComparison.OrdinalIgnoreCase);
    }

    public static void EnsureDistinct(string sourcePath, string destinationPath)
    {
        if (ReferToSameWindowsPath(sourcePath, destinationPath))
        {
            throw new IOException("The output path must not overwrite the selected source EPUB.");
        }
    }
}

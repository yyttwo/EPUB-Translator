using EPUBTranslator.Core;

namespace EPUBTranslator.Platform.Windows;

public sealed class WindowsAppDataPaths : IAppDataPaths
{
    public WindowsAppDataPaths()
        : this(CreateDefaultRoot())
    {
    }

    internal WindowsAppDataPaths(string rootDirectory)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(rootDirectory);

        RootDirectory = Path.GetFullPath(rootDirectory);
        StateDirectory = Path.Combine(RootDirectory, "State");
        CacheDirectory = Path.Combine(RootDirectory, "Cache");

        Directory.CreateDirectory(StateDirectory);
        Directory.CreateDirectory(CacheDirectory);
    }

    public string RootDirectory { get; }

    public string StateDirectory { get; }

    public string CacheDirectory { get; }

    private static string CreateDefaultRoot()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        if (string.IsNullOrWhiteSpace(localAppData))
        {
            throw new InvalidOperationException("Windows LocalApplicationData is unavailable.");
        }

        return Path.Combine(localAppData, "EPUBTranslator");
    }
}

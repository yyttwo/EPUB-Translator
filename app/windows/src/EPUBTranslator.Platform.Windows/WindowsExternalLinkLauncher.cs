using EPUBTranslator.Core;
using Windows.System;

namespace EPUBTranslator.Platform.Windows;

public sealed class WindowsExternalLinkLauncher : IExternalLinkLauncher
{
    public async ValueTask<bool> LaunchAsync(Uri uri, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(uri);
        cancellationToken.ThrowIfCancellationRequested();

        if (uri != SupportLinks.Feedback)
        {
            throw new InvalidOperationException("Only the approved feedback URL may be launched.");
        }

        var launched = await Launcher.LaunchUriAsync(uri);
        cancellationToken.ThrowIfCancellationRequested();
        return launched;
    }
}

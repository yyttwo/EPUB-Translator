using EPUBTranslator.Core;
using EPUBTranslator.Platform.Windows;
using Microsoft.UI;

namespace EPUBTranslator.App;

internal sealed record AppServices(
    ICredentialStore CredentialStore,
    ProviderCoordinator ProviderCoordinator,
    ProviderSessionState ProviderSessionState,
    IFileOpenPicker FileOpenPicker,
    IFileSavePicker FileSavePicker,
    IFileCopyService FileCopyService,
    IAppDataPaths AppDataPaths,
    IExternalLinkLauncher ExternalLinkLauncher)
{
    public static AppServices Create(WindowId windowId)
    {
        var picker = new WindowsFilePickerService(windowId);
        var credentialStore = new WindowsCredentialStore();
        var transport = new LazyProviderHttpTransport();
        var coordinator = new ProviderCoordinator(
            credentialStore,
            new ITranslationProvider[]
            {
                OpenAiCompatibleTranslationProvider.Create(ProviderId.Qwen, transport),
                OpenAiCompatibleTranslationProvider.Create(ProviderId.DeepSeek, transport),
            });
        return new AppServices(
            credentialStore,
            coordinator,
            new ProviderSessionState(),
            picker,
            picker,
            new WindowsFileCopyService(),
            new WindowsAppDataPaths(),
            new WindowsExternalLinkLauncher());
    }
}

using EPUBTranslator.Platform.Windows;
using Microsoft.UI;
using Microsoft.UI.Xaml;

namespace EPUBTranslator.App;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    internal static AppServices Services { get; private set; } = null!;

    internal static void InitializeServices(WindowId windowId)
    {
        Services = AppServices.Create(windowId);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow();
        _window.Activate();
    }
}

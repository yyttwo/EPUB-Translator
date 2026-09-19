namespace EPUBTranslator.Core;

public enum SupportedArchitecture
{
    X64,
    Arm64,
}

public static class SupportedArchitectures
{
    public static IReadOnlyList<SupportedArchitecture> All { get; } =
        [SupportedArchitecture.X64, SupportedArchitecture.Arm64];

    public static string RuntimeIdentifier(this SupportedArchitecture architecture) => architecture switch
    {
        SupportedArchitecture.X64 => "win-x64",
        SupportedArchitecture.Arm64 => "win-arm64",
        _ => throw new ArgumentOutOfRangeException(nameof(architecture), architecture, null),
    };

    public static string MsBuildPlatform(this SupportedArchitecture architecture) => architecture switch
    {
        SupportedArchitecture.X64 => "x64",
        SupportedArchitecture.Arm64 => "ARM64",
        _ => throw new ArgumentOutOfRangeException(nameof(architecture), architecture, null),
    };
}

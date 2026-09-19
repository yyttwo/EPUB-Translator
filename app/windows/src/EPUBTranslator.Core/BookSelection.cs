namespace EPUBTranslator.Core;

public sealed record BookSelection(string FullPath, string FileName, long SizeBytes)
{
    public string HumanReadableSize => SizeBytes switch
    {
        < 1_024 => $"{SizeBytes} B",
        < 1_048_576 => $"{SizeBytes / 1_024d:0.0} KB",
        _ => $"{SizeBytes / 1_048_576d:0.0} MB",
    };
}

namespace EPUBTranslator.Core;

public enum TranslationStyle
{
    Literal,
    Fluent,
    ConciseInterpretive,
    FormalCommentary,
}

public sealed record TranslationStyleDefinition(
    TranslationStyle Value,
    string StableId,
    string DisplayName,
    bool IsDefault = false);

public static class TranslationStyles
{
    public static IReadOnlyList<TranslationStyleDefinition> All { get; } =
    [
        new(TranslationStyle.Literal, "literal", "直译版"),
        new(TranslationStyle.Fluent, "fluent", "通畅版", IsDefault: true),
        new(TranslationStyle.ConciseInterpretive, "concise_interpretive", "意译（更简洁有力）"),
        new(TranslationStyle.FormalCommentary, "formal_commentary", "书面评论体"),
    ];

    public static TranslationStyleDefinition Default => All.Single(style => style.IsDefault);
}

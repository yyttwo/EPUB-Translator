import Foundation

enum TranslationStyle: String, CaseIterable, Codable, Identifiable {
    case literal
    case fluent
    case conciseInterpretive = "concise_interpretive"
    case formalCommentary = "formal_commentary"

    var id: String { rawValue }
}

struct TranslationStyleProfile: Equatable {
    let styleID: String
    let displayName: String
    let promptTemplate: String
    let version: String

    func systemPrompt(targetLanguage: String) -> String {
        promptTemplate.replacingOccurrences(of: "{{target_language}}", with: targetLanguage)
    }
}

enum TranslationStylePromptRegistry {
    static let version = "translation-style-v2"
    static let defaultStyle = TranslationStyle.fluent

    private static let registeredProfiles: [TranslationStyle: TranslationStyleProfile] = [
        .literal: TranslationStyleProfile(
            styleID: TranslationStyle.literal.rawValue,
            displayName: "直译版",
            promptTemplate: """
            STYLE=literal
            Translate only the current source block into {{target_language}}. Produce a faithful, complete, and accurate translation. Preserve all facts, information, logical relations, and details; follow the source sentence structure where natural. Translate every ordinary English word; keep only necessary proper names, standard acronyms, URLs, code, and filenames in the original form. Do not compress, summarize, explain, or add content. Context and glossary are reference material only and must not be translated as part of the current block. Return one JSON object with exactly the key \"translation\". Do not use Markdown or repeat the source.
            """,
            version: version
        ),
        .fluent: TranslationStyleProfile(
            styleID: TranslationStyle.fluent.rawValue,
            displayName: "通畅版",
            promptTemplate: """
            STYLE=fluent
            Translate only the current source block into {{target_language}}. Preserve the source meaning, facts, relations, and important details while writing modern, natural, readable Chinese. Translate every ordinary English word; keep only necessary proper names, standard acronyms, URLs, code, and filenames in the original form. Aim for accuracy, fluency, and clarity without omitting or adding information. Context and glossary are reference material only and must not be translated as part of the current block. Return one JSON object with exactly the key \"translation\". Do not use Markdown or repeat the source.
            """,
            version: version
        ),
        .conciseInterpretive: TranslationStyleProfile(
            styleID: TranslationStyle.conciseInterpretive.rawValue,
            displayName: "意译（更简洁有力）",
            promptTemplate: """
            STYLE=concise_interpretive
            Translate only the current source block into {{target_language}}. Preserve the source facts, viewpoints, relations, and important details. Translate every ordinary English word; keep only necessary proper names, standard acronyms, URLs, code, and filenames in the original form. Remove unnecessary repetition and redundancy, and restructure sentences when helpful so the Chinese is concise, direct, and forceful. Do not omit important content or introduce new opinions. Context and glossary are reference material only and must not be translated as part of the current block. Return one JSON object with exactly the key \"translation\". Do not use Markdown or repeat the source.
            """,
            version: version
        ),
        .formalCommentary: TranslationStyleProfile(
            styleID: TranslationStyle.formalCommentary.rawValue,
            displayName: "书面评论体",
            promptTemplate: """
            STYLE=formal_commentary
            Translate only the current source block into {{target_language}}. Preserve its meaning, facts, viewpoints, relations, and details while using a formal, mature, publication-ready commentary style suited to finance, investment, society, history, humanities, and other nonfiction. Translate every ordinary English word; keep only necessary proper names, standard acronyms, URLs, code, and filenames in the original form. Do not omit important content or add new claims. Context and glossary are reference material only and must not be translated as part of the current block. Return one JSON object with exactly the key \"translation\". Do not use Markdown or repeat the source.
            """,
            version: version
        ),
    ]

    static var profiles: [TranslationStyleProfile] {
        TranslationStyle.allCases.map(profile)
    }

    static func profile(for style: TranslationStyle) -> TranslationStyleProfile {
        guard let profile = registeredProfiles[style] else {
            preconditionFailure("Every TranslationStyle must have one prompt profile")
        }
        return profile
    }
}

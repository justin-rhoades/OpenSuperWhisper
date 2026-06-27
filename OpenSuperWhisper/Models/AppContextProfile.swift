import Foundation

/// Per-app formatting rules applied by the local LLM after transcription. When dictation lands
/// in a given app (matched by frontmost bundle identifier), `instructions` are folded into the
/// LLM system prompt so spoken shorthand is rewritten the way that app expects — e.g. in Slack
/// "at Rob" → "@Rob" and "slash giphy" → "/giphy".
///
/// This is independent of the general "AI Cleanup" prose pass: either can contribute to a single
/// LLM call (see `LLMPostProcessor.assembleSystemPrompt`).
struct AppContextProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleIdentifier: String   // e.g. "com.tinyspeck.slackmacgap"
    var appName: String            // display label, e.g. "Slack"
    var instructions: String       // natural-language formatting rules for the LLM

    init(id: UUID = UUID(), bundleIdentifier: String = "", appName: String = "", instructions: String = "") {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.instructions = instructions
    }
}

extension AppContextProfile {
    /// Seeded once so new users get a working example they can tweak or delete.
    static let slackPreset = AppContextProfile(
        bundleIdentifier: "com.tinyspeck.slackmacgap",
        appName: "Slack",
        instructions: """
        Convert spoken Slack shorthand into the symbols Slack expects:
        - A spoken mention like "at Rob" becomes "@Rob" (no space after the @).
        - A spoken slash-command like "slash giphy" becomes "/giphy".
        Only rewrite these when they are clearly meant as a mention or command. Leave all other \
        words exactly as written — do not add, remove, or rephrase anything else.
        """)

    /// The presets seeded into a fresh install (one-time; see `AppPreferences.seedAppContextPresetsIfNeeded`).
    static let defaultPresets: [AppContextProfile] = [slackPreset]
}

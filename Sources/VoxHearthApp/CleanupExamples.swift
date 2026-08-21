import Foundation
import VoxHearthCore

struct CleanupExample: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let original: String
    let cleaned: String
    let note: String
}

/// Fixed educational copy. Rendering these examples cannot prepare or invoke a
/// model because the values have no runtime dependency or callback.
enum CleanupExamples {
    static let all: [CleanupExample] = [
        CleanupExample(
            id: "ordinary",
            title: "Ordinary semi-formal cleanup",
            original: "um I think we should probably send the report on Thursday",
            cleaned: "I think we should send the report on Thursday.",
            note: "Filler and punctuation are cleaned up without changing the meaning."
        ),
        CleanupExample(
            id: "list",
            title: "A list command",
            original: "list milk eggs and bread",
            cleaned: "- Milk\n- Eggs\n- Bread",
            note: "Only a new dictation whose first word is “list” selects list mode; the command is removed."
        ),
        CleanupExample(
            id: "email",
            title: "An email command",
            original: "email hi John I can meet next week all the best Stephen",
            cleaned: "Hi John,\n\nI can meet next week.\n\nAll the best,\nStephen",
            note: "Only a new dictation whose first word is “email” selects email mode; the command is removed."
        ),
        CleanupExample(
            id: "near-misses",
            title: "Later mentions stay ordinary",
            original: "In reference to the list Michael sent, my email is unchanged.",
            cleaned: "In reference to the list Michael sent, my email is unchanged.",
            note: "“list” and “email” do nothing when they are not the first word."
        ),
    ]
}

struct CleanupTrialComparison: Equatable, Sendable {
    let sessionID: DictationSessionID
    let original: String
    let selected: String
    let directive: RecognizedDirective?

    var modeDescription: String {
        switch directive {
        case .list?:
            "List mode selected. The “list” command is removed before insertion."
        case .email?:
            "Email mode selected. The “email” command is removed before insertion."
        case nil:
            "Ordinary cleanup selected. No command word was removed."
        }
    }
}

import Foundation

/// Run independently of the app:
/// swiftc -parse-as-library Sources/EZSnapshot/Localization.swift \
///   Tests/LocalizationChecks.swift -o /tmp/EZSnapshotLocalizationChecks
/// /tmp/EZSnapshotLocalizationChecks
@main
struct LocalizationChecks {
    private enum CheckFailure: Error, CustomStringConvertible {
        case failed(String)

        var description: String {
            switch self {
            case .failed(let message): message
            }
        }
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw CheckFailure.failed(message) }
    }

    static func main() throws {
        let languages = AppLanguage.allCases.filter { $0 != .system }
        try check(languages.count == 8, "Expected eight explicit interface languages.")

        let expectedLocales: [AppLanguage: String] = [
            .enUS: "en_US", .zhCN: "zh_Hans_CN", .zhTW: "zh_Hant_TW",
            .jaJP: "ja_JP", .koKR: "ko_KR", .frFR: "fr_FR",
            .deDE: "de_DE", .esES: "es_ES",
        ]
        try check(Set(languages.map(\.flag)).count == languages.count,
                  "Each explicit language should display a distinct flag.")

        for language in languages {
            try check(language.resolved == language,
                      "Explicit language \(language.rawValue) should resolve to itself.")
            try check(language.localeIdentifier == expectedLocales[language],
                      "Incorrect locale identifier for \(language.rawValue).")
            try check(!language.nativeName.isEmpty && !language.flag.isEmpty,
                      "Missing native name or flag for \(language.rawValue).")
            try check(language.id == language.rawValue,
                      "Unstable identifier for \(language.rawValue).")

            for key in L10nKey.allCases {
                let value = language.string(key)
                try check(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          "Empty translation: \(language.rawValue).\(key.rawValue)")

                // These are legitimate English labels, identical to their stable
                // keys. All other labels must differ from a raw-key fallback.
                let isEnglishIdentityLabel = language == .enUS &&
                    (key == .screenshots || key == .seconds || key == .videos || key == .captures)
                try check(value != key.rawValue || isEnglishIdentityLabel,
                          "Raw-key fallback: \(language.rawValue).\(key.rawValue)")
            }

            let encoded = try JSONEncoder().encode(language)
            let decoded = try JSONDecoder().decode(AppLanguage.self, from: encoded)
            try check(decoded == language,
                      "Language preference did not survive encoding: \(language.rawValue).")
        }

        try check(AppLanguage.system.resolved != .system,
                  "System mode must resolve to a supported language.")
        try check(AppLanguage.system.localeIdentifier == AppLanguage.system.resolved.localeIdentifier,
                  "System mode should use its resolved language’s locale.")
        for key in L10nKey.allCases {
            try check(AppLanguage.system.string(key) == AppLanguage.system.resolved.string(key),
                      "System mode has an inconsistent translation for \(key.rawValue).")
        }

        print("Passed: \(L10nKey.allCases.count) keys × \(languages.count) languages; locale identifiers, flags, Codable preferences, and system resolution.")
    }
}

import Foundation

/// Loads real API captures from the repo-root `fixtures/` directory into tests.
///
/// Fixtures are the source of truth for all parsing in this project (AGENTS.md rule
/// 3) and live at `<repo root>/fixtures/*.json` — outside the SwiftPM package, since
/// they are shared with the app/widget targets too and symlinks are not practical on
/// a Windows-developed repo. This walks up from the calling file's `#filePath` at
/// runtime until it finds a `fixtures` directory, so it works regardless of where the
/// repo is checked out (CI runner, a future contributor's machine, ...).
enum FixtureLoader {
    enum FixtureLoaderError: Error, CustomStringConvertible {
        case notFound(String)

        var description: String {
            switch self {
            case .notFound(let name):
                return "Fixture '\(name).json' not found by walking up from #filePath"
            }
        }
    }

    /// Locates `fixtures/<name>.json` relative to the repo root.
    static func fixtureURL(_ name: String, file: StaticString = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("fixtures").appendingPathComponent("\(name).json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        throw FixtureLoaderError.notFound(name)
    }

    /// Loads the raw bytes of `fixtures/<name>.json`.
    static func load(_ name: String, file: StaticString = #filePath) throws -> Data {
        let url = try fixtureURL(name, file: file)
        return try Data(contentsOf: url)
    }

    /// Loads and parses `fixtures/<name>.json` as a generic JSON value.
    static func loadJSON(_ name: String, file: StaticString = #filePath) throws -> Any {
        let data = try load(name, file: file)
        return try JSONSerialization.jsonObject(with: data)
    }
}

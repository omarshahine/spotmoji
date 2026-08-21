import Foundation

struct StoredEmoji: Decodable {
    let emoji: String
    let name: String
}

struct EmojibaseEmoji: Decodable {
    struct Skin: Decodable {
        let emoji: String
    }

    let label: String
    let hexcode: String
    let tags: [String]?
    let emoji: String
    let skins: [Skin]?
}

enum ShortcodeValue: Decodable {
    case one(String)
    case many([String])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .one(value)
        } else {
            self = .many(try container.decode([String].self))
        }
    }

    var values: [String] {
        switch self {
        case .one(let value): [value]
        case .many(let values): values
        }
    }
}

struct SearchMetadata: Codable {
    var aliases: [String]
    var keywords: [String]
}

func normalizedEmoji(_ emoji: String) -> String {
    String(emoji.unicodeScalars.filter { $0.value != 0xFE0F })
}

func normalizedTerm(_ term: String) -> String {
    term
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .lowercased()
}

func uniqueTerms(_ terms: [String]) -> [String] {
    Array(Set(terms.map(normalizedTerm).filter { !$0.isEmpty })).sorted()
}

func curatedAliases(for emoji: String) -> [String] {
    switch normalizedEmoji(emoji) {
    case "✋", "🙌", "🙏": ["high five", "high 5"]
    default: []
    }
}

func metadataKey(for name: String) -> String {
    let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
    guard parts.count == 2, parts[1].contains("skin tone") else { return name }
    return parts[0]
}

guard CommandLine.arguments.count == 6 else {
    fputs(
        "usage: generate_search_metadata <emojis.json> <emojibase-data.json> "
            + "<emojilib.json> <emojibase-shortcodes-directory> <output.json>\n",
        stderr
    )
    exit(2)
}

let decoder = JSONDecoder()
let emojiURL = URL(fileURLWithPath: CommandLine.arguments[1])
let emojibaseURL = URL(fileURLWithPath: CommandLine.arguments[2])
let emojilibURL = URL(fileURLWithPath: CommandLine.arguments[3])
let shortcodesURL = URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[5])

let emojiItems = try decoder.decode([StoredEmoji].self, from: Data(contentsOf: emojiURL))
let emojibaseItems = try decoder.decode([EmojibaseEmoji].self, from: Data(contentsOf: emojibaseURL))
let emojilib = try decoder.decode([String: [String]].self, from: Data(contentsOf: emojilibURL))

let shortcodeNames = ["emojibase", "github", "iamcal", "joypixels"]
let shortcodePacks = try shortcodeNames.map { name in
    let url = shortcodesURL.appendingPathComponent("\(name).json")
    return try decoder.decode([String: ShortcodeValue].self, from: Data(contentsOf: url))
}

var metadataByEmoji: [String: SearchMetadata] = [:]
for item in emojibaseItems {
    let shortcodeTerms = shortcodePacks.flatMap { $0[item.hexcode]?.values ?? [] }
    let emojilibTerms = emojilib[item.emoji]
        ?? emojilib[normalizedEmoji(item.emoji)]
        ?? []
    let aliases = uniqueTerms(shortcodeTerms + emojilibTerms + curatedAliases(for: item.emoji))
    let keywords = uniqueTerms(item.tags ?? []).filter { !aliases.contains($0) }
    let metadata = SearchMetadata(aliases: aliases, keywords: keywords)

    metadataByEmoji[normalizedEmoji(item.emoji)] = metadata
    for skin in item.skins ?? [] {
        metadataByEmoji[normalizedEmoji(skin.emoji)] = metadata
    }
}

var output: [String: SearchMetadata] = [:]
var missing: [String] = []
for item in emojiItems {
    guard let metadata = metadataByEmoji[normalizedEmoji(item.emoji)] else {
        missing.append("\(item.emoji) \(item.name)")
        continue
    }

    let key = metadataKey(for: item.name)
    if var existing = output[key] {
        existing.aliases = uniqueTerms(existing.aliases + metadata.aliases)
        existing.keywords = uniqueTerms(existing.keywords + metadata.keywords)
        output[key] = existing
    } else {
        output[key] = metadata
    }
}

guard missing.isEmpty else {
    fputs("Missing search metadata for \(missing.count) emoji:\n", stderr)
    for item in missing.prefix(20) {
        fputs("- \(item)\n", stderr)
    }
    exit(1)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
try encoder.encode(output).write(to: outputURL, options: .atomic)
print("Generated search metadata for \(output.count) base emoji covering \(emojiItems.count) entries")

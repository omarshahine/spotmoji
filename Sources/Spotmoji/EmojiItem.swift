import Foundation

enum EmojiSearchText {
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func compact(_ value: String) -> String {
        value.filter { $0.isLetter || $0.isNumber }.lowercased()
    }
}

struct EmojiSearchField: Equatable, Sendable {
    let value: String
    let compactValue: String
    let tokens: [String]
    let weight: Int

    init(_ rawValue: String, weight: Int) {
        value = EmojiSearchText.normalize(rawValue)
        compactValue = EmojiSearchText.compact(value)
        tokens = value.split(separator: " ").map(String.init)
        self.weight = weight
    }
}

struct EmojiItem: Decodable, Equatable, Sendable {
    let emoji: String
    let name: String
    let group: String
    let subgroup: String
    let aliases: [String]
    let keywords: [String]
    let searchFields: [EmojiSearchField]

    init(
        emoji: String,
        name: String,
        group: String,
        subgroup: String,
        aliases: [String] = [],
        keywords: [String] = [],
        aliasSearchFields: [EmojiSearchField]? = nil,
        keywordSearchFields: [EmojiSearchField]? = nil
    ) {
        self.emoji = emoji
        self.name = name
        self.group = group
        self.subgroup = subgroup
        self.aliases = aliases
        self.keywords = keywords
        searchFields = [
            EmojiSearchField(name, weight: 0),
            EmojiSearchField(Self.shortcode(for: name), weight: 10),
        ]
        + (aliasSearchFields ?? aliases.map { EmojiSearchField($0, weight: 100) })
        + (keywordSearchFields ?? keywords.map { EmojiSearchField($0, weight: 250) })
        + [
            EmojiSearchField(group, weight: 400),
            EmojiSearchField(subgroup, weight: 410),
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case emoji, name, group, subgroup, aliases, keywords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            emoji: try container.decode(String.self, forKey: .emoji),
            name: try container.decode(String.self, forKey: .name),
            group: try container.decode(String.self, forKey: .group),
            subgroup: try container.decode(String.self, forKey: .subgroup),
            aliases: try container.decodeIfPresent([String].self, forKey: .aliases) ?? [],
            keywords: try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        )
    }

    var skinToneBaseName: String {
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[1].contains("skin tone") else { return name }
        return parts[0]
    }

    var isSkinToneVariant: Bool {
        emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
    }

    var shortcode: String {
        Self.shortcode(for: name)
    }

    private static func shortcode(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let words = name
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let slug = words.joined(separator: "_")
        return slug.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
    }
}

struct EmojiSearchMetadata: Decodable, Equatable {
    let aliases: [String]
    let keywords: [String]
    let aliasSearchFields: [EmojiSearchField]
    let keywordSearchFields: [EmojiSearchField]

    private enum CodingKeys: String, CodingKey {
        case aliases, keywords
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aliases = try container.decode([String].self, forKey: .aliases)
        keywords = try container.decode([String].self, forKey: .keywords)
        aliasSearchFields = aliases.map { EmojiSearchField($0, weight: 100) }
        keywordSearchFields = keywords.map { EmojiSearchField($0, weight: 250) }
    }
}

enum EmojiStore {
    static func load() throws -> [EmojiItem] {
        guard let emojiURL = Bundle.module.url(forResource: "emojis", withExtension: "json"),
              let searchURL = Bundle.module.url(forResource: "emoji-search", withExtension: "json")
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        let decoder = JSONDecoder()
        let items = try decoder.decode([EmojiItem].self, from: Data(contentsOf: emojiURL))
        let metadata = try decoder.decode(
            [String: EmojiSearchMetadata].self,
            from: Data(contentsOf: searchURL)
        )

        return try items.map { item in
            guard let search = metadata[item.skinToneBaseName] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return EmojiItem(
                emoji: item.emoji,
                name: item.name,
                group: item.group,
                subgroup: item.subgroup,
                aliases: search.aliases,
                keywords: search.keywords,
                aliasSearchFields: search.aliasSearchFields,
                keywordSearchFields: search.keywordSearchFields
            )
        }
    }
}

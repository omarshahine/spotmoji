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

    static func allowedEditDistance(for term: String) -> Int? {
        switch term.count {
        case 0...3: nil
        case 4...7: 1
        default: 2
        }
    }

    // Optimal-string-alignment distance catches both typos and adjacent transpositions.
    static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= limit else { return limit + 1 }

        var previousPrevious = Array(0...right.count)
        var previous = previousPrevious
        for leftIndex in 1...left.count {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex
            var rowMinimum = current[0]
            for rightIndex in 1...right.count {
                let substitution = previous[rightIndex - 1]
                    + (left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1)
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    substitution
                )
                if leftIndex > 1,
                   rightIndex > 1,
                   left[leftIndex - 1] == right[rightIndex - 2],
                   left[leftIndex - 2] == right[rightIndex - 1] {
                    current[rightIndex] = min(current[rightIndex], previousPrevious[rightIndex - 2] + 1)
                }
                rowMinimum = min(rowMinimum, current[rightIndex])
            }
            if rowMinimum > limit { return limit + 1 }
            previousPrevious = previous
            previous = current
        }
        return previous[right.count]
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

    func matchedAlias(for rawQuery: String) -> String? {
        let query = EmojiSearchText.normalize(rawQuery)
        guard !query.isEmpty else { return nil }

        let compactQuery = EmojiSearchText.compact(query)
        let normalizedName = EmojiSearchText.normalize(name)
        let candidates = aliases.compactMap { alias -> (alias: String, score: Int)? in
            let normalizedAlias = EmojiSearchText.normalize(alias)
            guard !normalizedAlias.isEmpty, normalizedAlias != normalizedName else { return nil }

            let compactAlias = EmojiSearchText.compact(normalizedAlias)
            if normalizedAlias == query { return (alias, 0) }
            if compactAlias == compactQuery { return (alias, 1) }
            if normalizedAlias.hasPrefix(query) { return (alias, 2) }
            if compactAlias.hasPrefix(compactQuery) { return (alias, 3) }
            if normalizedAlias.contains(query) { return (alias, 4) }
            if compactAlias.contains(compactQuery) { return (alias, 5) }
            return nil
        }

        if let match = candidates.min(by: {
            if $0.score != $1.score { return $0.score < $1.score }
            if $0.alias.count != $1.alias.count { return $0.alias.count < $1.alias.count }
            return $0.alias < $1.alias
        }) {
            return match.alias
        }

        let queryTerms = query.split(separator: " ").map(String.init)
        return aliases.compactMap { alias -> (alias: String, score: Int)? in
            let normalizedAlias = EmojiSearchText.normalize(alias)
            guard !normalizedAlias.isEmpty, normalizedAlias != normalizedName else { return nil }

            let aliasTerms = normalizedAlias.split(separator: " ").map(String.init)
            guard aliasTerms.count == queryTerms.count else { return nil }

            let distances = zip(queryTerms, aliasTerms).compactMap { queryTerm, aliasTerm -> Int? in
                guard let limit = EmojiSearchText.allowedEditDistance(for: queryTerm) else { return nil }
                let distance = EmojiSearchText.editDistance(queryTerm, aliasTerm, limit: limit)
                return distance <= limit ? distance : nil
            }
            guard distances.count == queryTerms.count else { return nil }
            return (alias, distances.reduce(0, +))
        }.min {
            if $0.score != $1.score { return $0.score < $1.score }
            if $0.alias.count != $1.alias.count { return $0.alias.count < $1.alias.count }
            return $0.alias < $1.alias
        }?.alias
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
        let resources = resourceBundle()
        guard let emojiURL = resources.url(forResource: "emojis", withExtension: "json"),
              let searchURL = resources.url(forResource: "emoji-search", withExtension: "json")
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

    /// SwiftPM's generated `Bundle.module` accessor looks beside `Spotmoji.app`
    /// when the executable is copied into a manually assembled app bundle. A
    /// standard macOS app stores SwiftPM resource bundles in Contents/Resources,
    /// so prefer that location and retain Bundle.module for tests and `swift run`.
    private static func resourceBundle() -> Bundle {
        if let appResources = packagedResourceBundle() {
            return appResources
        }

        return Bundle.module
    }

    static func packagedResourceBundle() -> Bundle? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        return Bundle(url: resourceURL.appendingPathComponent("Spotmoji_Spotmoji.bundle"))
    }
}

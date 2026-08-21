import Foundation

enum EmojiSearch {
    static func search(_ query: String, in items: [EmojiItem], limit: Int = 80) -> [EmojiItem] {
        let query = normalize(query)
        guard !query.isEmpty else { return Array(items.prefix(limit)) }

        let terms = query.split(separator: " ").map(String.init)
        return items.compactMap { item -> (EmojiItem, Int)? in
            let name = normalize(item.name)
            let shortcode = normalize(item.shortcode.replacingOccurrences(of: "_", with: " "))
            let group = normalize(item.group + " " + item.subgroup)
            let searchable = name + " " + shortcode + " " + group

            guard terms.allSatisfy({ term in
                searchable.contains(term)
                    || (term.hasSuffix("s") && searchable.contains(String(term.dropLast())))
            }) else { return nil }

            let score: Int
            if name == query || shortcode == query {
                score = 0
            } else if name.hasPrefix(query) || shortcode.hasPrefix(query) {
                score = 10
            } else if name.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
                score = 20
            } else if name.contains(query) || shortcode.contains(query) {
                score = 30
            } else {
                score = 40
            }
            return (item, score)
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.0.name.count != $1.0.name.count { return $0.0.name.count < $1.0.name.count }
            return $0.0.name < $1.0.name
        }
        .prefix(limit)
        .map(\.0)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

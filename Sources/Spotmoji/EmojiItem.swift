import Foundation

struct EmojiItem: Codable, Equatable, Sendable {
    let emoji: String
    let name: String
    let group: String
    let subgroup: String

    var shortcode: String {
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

enum EmojiStore {
    static func load() throws -> [EmojiItem] {
        guard let url = Bundle.module.url(forResource: "emojis", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([EmojiItem].self, from: Data(contentsOf: url))
    }
}

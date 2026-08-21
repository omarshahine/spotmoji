import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

enum EmojiSpotlightIndex {
    private static let domainIdentifier = "emoji"
    private static let indexedVersionKey = "EmojiSpotlightIndex.indexedVersion"
    private static let schemaVersion = 4

    static func identifier(for item: EmojiItem) -> String {
        let scalars = item.emoji.unicodeScalars
            .map { String($0.value, radix: 16) }
            .joined(separator: "-")
        return "emoji:\(scalars)"
    }

    static func searchableItem(for item: EmojiItem) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = "\(item.emoji) \(item.name)"
        attributes.displayName = "\(item.emoji) \(item.name)"
        attributes.contentDescription = ":\(item.shortcode): • \(item.group)"
        attributes.containerTitle = "Spotmoji"
        attributes.kind = "Emoji"
        attributes.rankingHint = 1

        let nameTerms = item.name
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let pluralTerms = nameTerms
            .filter { !$0.hasSuffix("s") }
            .map { $0 + "s" }
        attributes.keywords = Array(Set(
            ["Spotmoji", "emoji", item.emoji, item.name, item.shortcode, item.group, item.subgroup]
                + nameTerms
                + pluralTerms
                + item.aliases
                + item.keywords
        ))
        attributes.textContent = attributes.keywords?.joined(separator: " ")

        let searchableItem = CSSearchableItem(
            uniqueIdentifier: identifier(for: item),
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        searchableItem.expirationDate = .distantFuture
        return searchableItem
    }

    static func indexIfNeeded(_ items: [EmojiItem]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }

        let indexedVersion = "\(schemaVersion)-\(items.count)"
        guard UserDefaults.standard.string(forKey: indexedVersionKey) != indexedVersion else { return }

        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { error in
            guard error == nil else { return }
            let searchableItems = itemsForIndexing(items).map(searchableItem(for:))
            CSSearchableIndex.default().indexSearchableItems(searchableItems) { error in
                guard error == nil else { return }
                UserDefaults.standard.set(indexedVersion, forKey: indexedVersionKey)
            }
        }
    }

    static func itemsForIndexing(_ items: [EmojiItem]) -> [EmojiItem] {
        items.filter { !$0.isSkinToneVariant }
    }
}

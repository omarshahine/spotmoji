import XCTest
@testable import Spotmoji

final class EmojiSearchTests: XCTestCase {
    private let items = [
        EmojiItem(emoji: "😀", name: "grinning face", group: "Smileys & Emotion", subgroup: "face-smiling"),
        EmojiItem(emoji: "😢", name: "crying face", group: "Smileys & Emotion", subgroup: "face-concerned"),
        EmojiItem(emoji: "🚀", name: "rocket", group: "Travel & Places", subgroup: "transport-air"),
        EmojiItem(emoji: "❤️", name: "red heart", group: "Smileys & Emotion", subgroup: "emotion"),
    ]

    func testExactNameRanksFirst() {
        XCTAssertEqual(EmojiSearch.search("rocket", in: items).first?.emoji, "🚀")
    }

    func testSearchMatchesMultipleTermsAcrossMetadata() {
        XCTAssertEqual(EmojiSearch.search("red emotion", in: items).map(\.emoji), ["❤️"])
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(EmojiSearch.search("CRY", in: items).first?.emoji, "😢")
    }

    func testEmptySearchHonorsLimit() {
        XCTAssertEqual(EmojiSearch.search("", in: items, limit: 2).count, 2)
    }

    func testPluralQueryMatchesSingularEmojiName() {
        let thread = EmojiItem(
            emoji: "🧵",
            name: "thread",
            group: "Activities",
            subgroup: "arts & crafts"
        )
        XCTAssertEqual(EmojiSearch.search("threads", in: [thread]).first?.emoji, "🧵")
    }

    func testSpotlightItemIncludesPluralKeyword() {
        let thread = EmojiItem(
            emoji: "🧵",
            name: "thread",
            group: "Activities",
            subgroup: "arts & crafts"
        )
        let searchableItem = EmojiSpotlightIndex.searchableItem(for: thread)

        XCTAssertEqual(searchableItem.uniqueIdentifier, "emoji:1f9f5")
        XCTAssertEqual(searchableItem.attributeSet.title, "🧵 thread")
        XCTAssertEqual(searchableItem.attributeSet.containerTitle, "Spotmoji")
        XCTAssertEqual(searchableItem.attributeSet.kind, "Emoji")
        XCTAssertTrue(searchableItem.attributeSet.keywords?.contains("Spotmoji") == true)
        XCTAssertTrue(searchableItem.attributeSet.keywords?.contains("threads") == true)
    }

    @MainActor
    func testTargetDetectorRejectsUtilitiesAndUnidentifiedProcesses() {
        XCTAssertFalse(TargetAppDetector.isEligible(
            bundleIdentifier: "app.cotypist.Cotypist",
            localizedName: "Cotypist",
            activationPolicy: .accessory
        ))
        XCTAssertFalse(TargetAppDetector.isEligible(
            bundleIdentifier: nil,
            localizedName: "Microsoft Teams ModuleHost",
            activationPolicy: .regular
        ))
        XCTAssertTrue(TargetAppDetector.isEligible(
            bundleIdentifier: "com.apple.systempreferences",
            localizedName: "System Settings",
            activationPolicy: .regular
        ))
    }
}

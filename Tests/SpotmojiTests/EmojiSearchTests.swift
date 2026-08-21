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
        XCTAssertTrue(EmojiSearch.search("", in: items, limit: 0).isEmpty)
    }

    func testPunctuationOnlySearchBehavesLikeAnEmptyQuery() {
        XCTAssertEqual(EmojiSearch.search("!!!", in: items, limit: 2), Array(items.prefix(2)))
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

    func testBundledMetadataCoversEveryEmoji() throws {
        let bundledItems = try EmojiStore.load()

        XCTAssertEqual(bundledItems.count, 3_944)
        XCTAssertTrue(bundledItems.allSatisfy { !$0.aliases.isEmpty || !$0.keywords.isEmpty })
    }

    func testHighFiveHumanPhrasesRankRaisedAndFoldedHands() throws {
        let bundledItems = try EmojiStore.load()

        for query in ["high five", "high 5", "highfive"] {
            let results = EmojiSearch.search(query, in: bundledItems)
            XCTAssertEqual(results.first?.emoji, "✋", "Unexpected first result for \(query)")
            XCTAssertTrue(results.prefix(5).contains(where: { $0.emoji == "🙌" }), query)
            XCTAssertTrue(results.prefix(5).contains(where: { $0.emoji == "🙏" }), query)
        }
    }

    func testMatchedHumanAliasCanBeShownInResults() throws {
        let bundledItems = try EmojiStore.load()
        let raisedHand = try XCTUnwrap(bundledItems.first(where: { $0.emoji == "✋" }))

        XCTAssertEqual(raisedHand.matchedAlias(for: "high five"), "high five")
        XCTAssertEqual(raisedHand.matchedAlias(for: "high 5"), "high 5")
        XCTAssertEqual(raisedHand.matchedAlias(for: "highf"), "highfive")
        XCTAssertNil(raisedHand.matchedAlias(for: "raised hand"))
    }

    func testStrongAliasOutranksBroadConceptKeyword() throws {
        let results = EmojiSearch.search("party", in: try EmojiStore.load())

        XCTAssertEqual(results.first?.emoji, "🥳")
    }

    func testCommonHumanAliases() throws {
        let bundledItems = try EmojiStore.load()

        XCTAssertEqual(EmojiSearch.search("coder", in: bundledItems).first?.emoji, "🧑‍💻")
        XCTAssertEqual(EmojiSearch.search("face palm", in: bundledItems).first?.emoji, "🤦")
        XCTAssertEqual(EmojiSearch.search("facepalm", in: bundledItems).first?.emoji, "🤦")
    }

    func testTypoToleranceHandlesTransposedLetters() throws {
        let results = EmojiSearch.search("laughign", in: try EmojiStore.load())

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.prefix(10).contains(where: { $0.aliases.contains("laughing") }))
        let laughingResult = try XCTUnwrap(results.first(where: { $0.aliases.contains("laughing") }))
        XCTAssertEqual(laughingResult.matchedAlias(for: "laughign"), "laughing")
    }

    func testSkinToneVariantsAreCollapsedUnlessRequested() throws {
        let bundledItems = try EmojiStore.load()
        let generalResults = EmojiSearch.search("high five", in: bundledItems)
        let raisedHands = generalResults.filter { $0.skinToneBaseName == "raised hand" }

        XCTAssertEqual(raisedHands.map(\.emoji), ["✋"])
        XCTAssertEqual(
            EmojiSearch.search("raised hand medium skin tone", in: bundledItems).first?.emoji,
            "✋🏽"
        )
    }

    func testSpotlightItemIncludesPluralAndSearchMetadata() throws {
        let bundledItems = try EmojiStore.load()
        let thread = try XCTUnwrap(bundledItems.first(where: { $0.emoji == "🧵" }))
        let raisedHand = try XCTUnwrap(bundledItems.first(where: { $0.emoji == "✋" }))
        let threadItem = EmojiSpotlightIndex.searchableItem(for: thread)
        let raisedHandItem = EmojiSpotlightIndex.searchableItem(for: raisedHand)

        XCTAssertEqual(threadItem.uniqueIdentifier, "emoji:1f9f5")
        XCTAssertEqual(threadItem.attributeSet.title, "🧵 thread")
        XCTAssertEqual(threadItem.attributeSet.containerTitle, "Spotmoji")
        XCTAssertEqual(threadItem.attributeSet.kind, "Emoji")
        XCTAssertTrue(threadItem.attributeSet.keywords?.contains("Spotmoji") == true)
        XCTAssertTrue(threadItem.attributeSet.keywords?.contains("threads") == true)
        XCTAssertTrue(raisedHandItem.attributeSet.keywords?.contains("high five") == true)
        XCTAssertTrue(raisedHandItem.attributeSet.keywords?.contains("5") == true)
    }

    func testSpotlightIndexOmitsSkinToneDuplicates() throws {
        let bundledItems = try EmojiStore.load()
        let indexedItems = EmojiSpotlightIndex.itemsForIndexing(bundledItems)

        XCTAssertFalse(indexedItems.contains(where: \.isSkinToneVariant))
        XCTAssertEqual(indexedItems.count, bundledItems.filter { !$0.isSkinToneVariant }.count)
    }

    @MainActor
    func testUpdateProbeIsThrottled() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertTrue(UpdateManager.shouldProbe(lastProbeDate: nil, now: now))
        XCTAssertFalse(UpdateManager.shouldProbe(lastProbeDate: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(UpdateManager.shouldProbe(
            lastProbeDate: now.addingTimeInterval(-UpdateManager.probeInterval),
            now: now
        ))
    }

    @MainActor
    func testUpdateProbeIsPersistedOnlyAfterCompletion() {
        let suiteName = "SpotmojiTests.UpdateProbe.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = UpdateManager(defaults: defaults)
        let startedAt = Date(timeIntervalSince1970: 1_000_000)
        let completedAt = startedAt.addingTimeInterval(2)

        XCTAssertTrue(manager.beginProbeIfNeeded(now: startedAt))
        XCTAssertFalse(manager.beginProbeIfNeeded(now: startedAt))
        XCTAssertTrue(UpdateManager.shouldProbe(lastProbeDate: nil, now: completedAt))

        manager.finishProbe(now: completedAt)

        XCTAssertFalse(manager.beginProbeIfNeeded(now: completedAt))
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

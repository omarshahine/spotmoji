import Foundation

enum EmojiSearch {
    static func search(_ rawQuery: String, in items: [EmojiItem], limit: Int = 80) -> [EmojiItem] {
        guard limit > 0 else { return [] }
        let query = EmojiSearchText.normalize(rawQuery)
        let includesSkinTone = query.split(separator: " ").contains { $0 == "skin" || $0 == "tone" }

        var ranked: [(item: EmojiItem, score: Int, index: Int)]
        if query.isEmpty {
            ranked = items.enumerated().map { ($0.element, 0, $0.offset) }
        } else {
            let candidates = includesSkinTone ? items : items.filter { !$0.isSkinToneVariant }
            ranked = rankedItems(for: query, in: candidates)
            if ranked.isEmpty,
               let correctedQuery = correctedQuery(for: query, in: candidates),
               correctedQuery != query {
                ranked = rankedItems(for: correctedQuery, in: candidates)
            }
        }

        var seenBaseNames = Set<String>()
        var results: [EmojiItem] = []
        for result in ranked {
            if !includesSkinTone {
                guard seenBaseNames.insert(result.item.skinToneBaseName).inserted else { continue }
            }
            results.append(result.item)
            if results.count == limit { break }
        }
        return results
    }

    private static func rankedItems(
        for query: String,
        in items: [EmojiItem]
    ) -> [(item: EmojiItem, score: Int, index: Int)] {
        items.enumerated().compactMap { index, item in
            score(item, for: query).map { (item, $0, index) }
        }
        .sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            return $0.index < $1.index
        }
    }

    private static func score(_ item: EmojiItem, for query: String) -> Int? {
        let fields = item.searchFields
        let compactQuery = EmojiSearchText.compact(query)

        if let phraseScore = fields.compactMap({ phraseScore(
            query: query,
            compactQuery: compactQuery,
            field: $0
        ) }).min() {
            return phraseScore
        }

        let queryTerms = query.split(separator: " ").map(String.init)
        let tokenScores = queryTerms.compactMap { term -> Int? in
            fields.compactMap { field in
                field.tokens.compactMap { tokenMatchScore(term, candidate: $0) }
                    .min()
                    .map { field.weight + $0 }
            }.min()
        }

        guard tokenScores.count == queryTerms.count else { return nil }
        return (tokenScores.max() ?? 0) + tokenScores.reduce(0, +) / 20 + 60
    }

    private static func phraseScore(
        query: String,
        compactQuery: String,
        field: EmojiSearchField
    ) -> Int? {
        guard !field.value.isEmpty else { return nil }
        if field.value == query { return field.weight }
        if field.compactValue == compactQuery { return field.weight + 3 }
        if field.value.hasPrefix(query) { return field.weight + 10 }
        if field.compactValue.hasPrefix(compactQuery) { return field.weight + 13 }
        if field.value.contains(query) { return field.weight + 20 }
        if field.compactValue.contains(compactQuery) { return field.weight + 23 }
        return nil
    }

    private static func tokenMatchScore(_ query: String, candidate: String) -> Int? {
        if candidate == query { return 0 }
        if singular(query) == singular(candidate) { return 4 }
        if candidate.hasPrefix(query) { return 10 }
        if query.count >= 3, candidate.contains(query) { return 20 }

        return nil
    }

    private static func correctedQuery(for query: String, in items: [EmojiItem]) -> String? {
        var vocabulary: [String: Int] = [:]
        for item in items {
            for field in item.searchFields {
                for token in field.tokens {
                    vocabulary[token] = min(vocabulary[token] ?? field.weight, field.weight)
                }
            }
        }

        var changed = false
        let correctedTerms = query.split(separator: " ").map(String.init).map { term -> String in
            if vocabulary[term] != nil { return term }

            guard let allowedDistance = EmojiSearchText.allowedEditDistance(for: term) else {
                return term
            }

            let best = vocabulary.compactMap { candidate, weight -> (String, Int, Int)? in
                guard abs(candidate.count - term.count) <= allowedDistance else { return nil }
                let distance = EmojiSearchText.editDistance(term, candidate, limit: allowedDistance)
                return distance <= allowedDistance ? (candidate, distance, weight) : nil
            }.min {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                if $0.2 != $1.2 { return $0.2 < $1.2 }
                return $0.0 < $1.0
            }

            guard let best else { return term }
            changed = true
            return best.0
        }
        return changed ? correctedTerms.joined(separator: " ") : nil
    }

    private static func singular(_ value: String) -> String {
        value.count > 3 && value.hasSuffix("s") ? String(value.dropLast()) : value
    }

}

import Foundation

struct EmojiItem: Codable {
    let emoji: String
    let name: String
    let group: String
    let subgroup: String
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate_emoji_data <emoji-test.txt> <emojis.json>\n", stderr)
    exit(2)
}

let input = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
var group = ""
var subgroup = ""
var items: [EmojiItem] = []

for rawLine in input.split(separator: "\n", omittingEmptySubsequences: false) {
    let line = String(rawLine)
    if line.hasPrefix("# group: ") {
        group = String(line.dropFirst("# group: ".count))
        continue
    }
    if line.hasPrefix("# subgroup: ") {
        subgroup = String(line.dropFirst("# subgroup: ".count))
        continue
    }
    guard line.contains("; fully-qualified"), let hash = line.firstIndex(of: "#") else { continue }

    let comment = line[line.index(after: hash)...].trimmingCharacters(in: .whitespaces)
    let parts = comment.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
    guard parts.count == 3, parts[1].hasPrefix("E") else { continue }

    items.append(EmojiItem(
        emoji: String(parts[0]),
        name: String(parts[2]),
        group: group,
        subgroup: subgroup
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(items)
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
print("Generated \(items.count) emoji entries")

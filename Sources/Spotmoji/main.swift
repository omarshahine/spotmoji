import AppKit

if CommandLine.arguments.contains("--validate-resources") {
    do {
        guard let packagedResources = EmojiStore.packagedResourceBundle(),
              packagedResources.url(forResource: "emojis", withExtension: "json") != nil,
              packagedResources.url(forResource: "emoji-search", withExtension: "json") != nil
        else {
            FileHandle.standardError.write(Data("Packaged Spotmoji resources are missing\n".utf8))
            exit(EXIT_FAILURE)
        }

        let items = try EmojiStore.load()
        guard !items.isEmpty else {
            FileHandle.standardError.write(Data("Spotmoji emoji data is empty\n".utf8))
            exit(EXIT_FAILURE)
        }
        print("Loaded \(items.count) emoji records")
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Could not load Spotmoji resources: \(error)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()

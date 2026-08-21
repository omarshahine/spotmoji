import AppKit

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PickerWindowController: NSWindowController, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let allItems: [EmojiItem]
    private var filteredItems: [EmojiItem]
    private let onChoose: (EmojiItem) -> Void
    private let onCancel: () -> Void

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")

    init(items: [EmojiItem], onChoose: @escaping (EmojiItem) -> Void, onCancel: @escaping () -> Void) {
        self.allItems = items
        self.filteredItems = Array(items.prefix(80))
        self.onChoose = onChoose
        self.onCancel = onCancel

        let panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 450),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false

        super.init(window: panel)
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showPicker(searchQuery: String = "") {
        guard let window else { return }
        searchField.stringValue = searchQuery
        filteredItems = EmojiSearch.search(searchQuery, in: allItems)
        tableView.reloadData()
        select(row: filteredItems.isEmpty ? -1 : 0)
        updatePermissionStatus()

        if let screen = NSScreen.main {
            let frame = window.frame
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.maxY - frame.height - min(100, visible.height * 0.12)
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)
    }

    func showMessage(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.textColor = .systemOrange
    }

    func updatePermissionStatus() {
        if PasteCoordinator.isAccessibilityEnabled {
            statusLabel.stringValue = "↑↓ navigate   ↩ paste   esc close"
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "Enable Accessibility once to paste directly. Selection still copies."
            statusLabel.textColor = .systemOrange
        }
    }

    private func configureUI() {
        guard let window else { return }

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = effect

        searchField.placeholderString = "Search emoji…"
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 16, weight: .regular)
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("emoji"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 46
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(chooseSelected)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(searchField)
        effect.addSubview(separator)
        effect.addSubview(scrollView)
        effect.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: effect.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -18),
            searchField.heightAnchor.constraint(equalToConstant: 48),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            separator.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: effect.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -8),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func controlTextDidChange(_ notification: Notification) {
        filteredItems = EmojiSearch.search(searchField.stringValue, in: allItems)
        tableView.reloadData()
        select(row: filteredItems.isEmpty ? -1 : 0)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            select(row: min(max(tableView.selectedRow, -1) + 1, filteredItems.count - 1))
            return true
        case #selector(NSResponder.moveUp(_:)):
            select(row: max(tableView.selectedRow - 1, 0))
            return true
        case #selector(NSResponder.insertNewline(_:)):
            chooseSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel()
            return true
        default:
            return false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filteredItems[row]
        let cell = NSTableCellView()

        let emoji = NSTextField(labelWithString: item.emoji)
        emoji.font = .systemFont(ofSize: 28)
        emoji.alignment = .center
        emoji.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: item.name)
        name.font = .systemFont(ofSize: 15, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        name.translatesAutoresizingMaskIntoConstraints = false
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let shortcode = NSTextField(labelWithString: ":\(item.shortcode):")
        shortcode.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        shortcode.textColor = .tertiaryLabelColor
        shortcode.alignment = .right
        shortcode.lineBreakMode = .byTruncatingMiddle
        shortcode.translatesAutoresizingMaskIntoConstraints = false
        shortcode.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        cell.addSubview(emoji)
        cell.addSubview(name)
        cell.addSubview(shortcode)
        NSLayoutConstraint.activate([
            emoji.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            emoji.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            emoji.widthAnchor.constraint(equalToConstant: 42),

            name.leadingAnchor.constraint(equalTo: emoji.trailingAnchor, constant: 12),
            name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: shortcode.leadingAnchor, constant: -12),

            shortcode.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
            shortcode.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            shortcode.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
        ])
        return cell
    }

    @objc private func chooseSelected() {
        let row = tableView.selectedRow
        guard filteredItems.indices.contains(row) else { return }
        onChoose(filteredItems[row])
    }

    private func select(row: Int) {
        guard row >= 0, filteredItems.indices.contains(row) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }
}

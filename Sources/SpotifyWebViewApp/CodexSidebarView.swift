import AppKit

@MainActor
final class SpotifyCodexSidebarView: NSVisualEffectView {
    var onSend: (String) -> Void = { _ in }
    var onRefreshModels: () -> Void = {}
    var onModelSelected: (String?) -> Void = { _ in }
    var onReasoningSelected: (String?) -> Void = { _ in }
    var onResetChat: () -> Void = {}
    var onClose: () -> Void = {}

    private let titleLabel = NSTextField(labelWithString: "Codex")
    private let closeButton = NSButton()
    private let resetButton = NSButton()
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reasoningPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let scrollView = NSScrollView()
    private let messageStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private var bubbleTextFields: [UUID: NSTextField] = [:]
    private var isBusy = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setCodexStatus(_ status: String) {
        toolTip = status
    }

    func setProviderContext(_ context: String) {
        modelPopup.toolTip = context
        reasoningPopup.toolTip = context
    }

    func setBusy(_ busy: Bool) {
        isBusy = busy
        sendButton.isEnabled = !busy
        sendButton.alphaValue = busy ? 0.45 : 1
    }

    func setModels(
        _ models: [SpotifyCodexModelOption],
        selectedModelID: String?,
        reasoning: [String],
        selectedReasoning: String?
    ) {
        modelPopup.removeAllItems()
        if models.isEmpty {
            modelPopup.addItem(withTitle: "Model")
            modelPopup.isEnabled = false
        } else {
            modelPopup.isEnabled = true
            for model in models {
                modelPopup.addItem(withTitle: model.displayName)
                modelPopup.lastItem?.representedObject = model.id
            }
            if let selectedModelID,
               let item = modelPopup.itemArray.first(where: { ($0.representedObject as? String) == selectedModelID }) {
                modelPopup.select(item)
            }
        }

        reasoningPopup.removeAllItems()
        if reasoning.isEmpty {
            reasoningPopup.addItem(withTitle: "Effort")
            reasoningPopup.isEnabled = false
        } else {
            reasoningPopup.isEnabled = true
            for effort in reasoning {
                reasoningPopup.addItem(withTitle: effort.capitalized)
                reasoningPopup.lastItem?.representedObject = effort
            }
            if let selectedReasoning,
               let item = reasoningPopup.itemArray.first(where: { ($0.representedObject as? String) == selectedReasoning }) {
                reasoningPopup.select(item)
            }
        }
    }

    func appendMessage(_ message: SpotifyCodexChatMessage) {
        let row = BubbleRowView(message: message)
        row.translatesAutoresizingMaskIntoConstraints = false
        messageStack.addArrangedSubview(row)
        bubbleTextFields[message.id] = row.textField
        row.widthAnchor.constraint(equalTo: messageStack.widthAnchor).isActive = true
        scrollToBottom()
    }

    func updateMessage(id: UUID, text: String) {
        bubbleTextFields[id]?.stringValue = text.isEmpty ? " " : text
        scrollToBottom()
    }

    func clearMessages() {
        bubbleTextFields.removeAll()
        for view in messageStack.arrangedSubviews {
            messageStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    func focusComposer() {
        window?.makeFirstResponder(inputField)
    }

    private func configure() {
        appearance = NSAppearance(named: .darkAqua)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.28
        layer?.shadowRadius = 22
        layer?.shadowOffset = CGSize(width: -8, height: 0)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        configureHeader(in: root)
        configureMessages(in: root)
        configureComposer(in: root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.topAnchor.constraint(equalTo: topAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func configureHeader(in root: NSStackView) {
        let codexMark = NSTextField(labelWithString: "C")
        codexMark.alignment = .center
        codexMark.font = .systemFont(ofSize: 12, weight: .bold)
        codexMark.textColor = .black
        codexMark.wantsLayer = true
        codexMark.layer?.cornerRadius = 10
        codexMark.layer?.backgroundColor = NSColor.spotifyGreen.cgColor
        codexMark.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white.withAlphaComponent(0.92)

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Close Codex")
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 15
        closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        closeButton.contentTintColor = .white.withAlphaComponent(0.84)
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.setAccessibilityLabel("Close Codex")
        closeButton.toolTip = "Close Codex"

        let header = NSStackView(views: [codexMark, titleLabel, NSView(), closeButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 9
        header.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(header)
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            codexMark.widthAnchor.constraint(equalToConstant: 20),
            codexMark.heightAnchor.constraint(equalToConstant: 20),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    private func configureMessages(in root: NSStackView) {
        messageStack.orientation = .vertical
        messageStack.alignment = .leading
        messageStack.spacing = 12
        messageStack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 12, right: 0)
        messageStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.documentView = messageStack
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        root.addArrangedSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360),
            messageStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    private func configureComposer(in root: NSStackView) {
        let composer = NSVisualEffectView()
        composer.appearance = NSAppearance(named: .darkAqua)
        composer.material = .hudWindow
        composer.blendingMode = .withinWindow
        composer.state = .active
        composer.wantsLayer = true
        composer.layer?.cornerRadius = 22
        composer.layer?.masksToBounds = true
        composer.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        composer.layer?.borderWidth = 1
        composer.translatesAutoresizingMaskIntoConstraints = false

        let composerStack = NSStackView()
        composerStack.orientation = .vertical
        composerStack.alignment = .leading
        composerStack.spacing = 8
        composerStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 9, right: 8)
        composerStack.translatesAutoresizingMaskIntoConstraints = false
        composer.addSubview(composerStack)

        configureSelector(modelPopup, placeholder: "Model")
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)

        configureSelector(reasoningPopup, placeholder: "Effort")
        reasoningPopup.target = self
        reasoningPopup.action = #selector(reasoningChanged)

        resetButton.title = ""
        resetButton.image = NSImage(systemSymbolName: "plus.bubble", accessibilityDescription: "New Chat")
        resetButton.imagePosition = .imageOnly
        resetButton.imageScaling = .scaleProportionallyDown
        resetButton.bezelStyle = .regularSquare
        resetButton.isBordered = false
        resetButton.wantsLayer = true
        resetButton.layer?.cornerRadius = 13
        resetButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        resetButton.contentTintColor = .white.withAlphaComponent(0.78)
        resetButton.target = self
        resetButton.action = #selector(resetPressed)
        resetButton.setAccessibilityLabel("New Chat")
        resetButton.toolTip = "New Chat"

        let selectorRow = NSStackView(views: [modelPopup, reasoningPopup, NSView(), resetButton])
        selectorRow.orientation = .horizontal
        selectorRow.alignment = .centerY
        selectorRow.spacing = 8
        selectorRow.translatesAutoresizingMaskIntoConstraints = false
        composerStack.addArrangedSubview(selectorRow)

        inputField.placeholderString = "Message Codex"
        inputField.font = .systemFont(ofSize: 14, weight: .regular)
        inputField.textColor = .white
        inputField.isBezeled = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.target = self
        inputField.action = #selector(sendPressed)
        inputField.setAccessibilityLabel("Message Codex")

        sendButton.title = ""
        sendButton.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "Send")
        sendButton.imagePosition = .imageOnly
        sendButton.imageScaling = .scaleProportionallyDown
        sendButton.bezelStyle = .regularSquare
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius = 15
        sendButton.layer?.backgroundColor = NSColor.spotifyGreen.cgColor
        sendButton.contentTintColor = .black
        sendButton.target = self
        sendButton.action = #selector(sendPressed)
        sendButton.setAccessibilityLabel("Send")
        sendButton.toolTip = "Send"

        let inputRow = NSStackView(views: [inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 8
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        composerStack.addArrangedSubview(inputRow)

        root.addArrangedSubview(composer)
        NSLayoutConstraint.activate([
            composer.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -28),
            composerStack.leadingAnchor.constraint(equalTo: composer.leadingAnchor),
            composerStack.trailingAnchor.constraint(equalTo: composer.trailingAnchor),
            composerStack.topAnchor.constraint(equalTo: composer.topAnchor),
            composerStack.bottomAnchor.constraint(equalTo: composer.bottomAnchor),
            selectorRow.widthAnchor.constraint(equalTo: composerStack.widthAnchor, constant: -18),
            inputRow.widthAnchor.constraint(equalTo: composerStack.widthAnchor, constant: -18),
            modelPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            reasoningPopup.widthAnchor.constraint(equalToConstant: 94),
            resetButton.widthAnchor.constraint(equalToConstant: 26),
            resetButton.heightAnchor.constraint(equalToConstant: 26),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 30),
            inputField.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])
    }

    private func configureSelector(_ popup: NSPopUpButton, placeholder: String) {
        popup.addItem(withTitle: placeholder)
        popup.font = .systemFont(ofSize: 11, weight: .medium)
        popup.controlSize = .small
        popup.bezelStyle = .texturedRounded
        popup.isBordered = false
        popup.wantsLayer = true
        popup.layer?.cornerRadius = 12
        popup.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        popup.contentTintColor = .white.withAlphaComponent(0.84)
    }

    private func scrollToBottom() {
        layoutSubtreeIfNeeded()
        guard let documentView = scrollView.documentView else { return }
        let visibleRect = NSRect(
            x: 0,
            y: max(documentView.bounds.height - scrollView.contentView.bounds.height, 0),
            width: 1,
            height: 1
        )
        documentView.scrollToVisible(visibleRect)
    }

    @objc private func sendPressed() {
        guard !isBusy else { return }
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""
        onSend(text)
    }

    @objc private func resetPressed() {
        onResetChat()
        focusComposer()
    }

    @objc private func modelChanged() {
        onModelSelected(modelPopup.selectedItem?.representedObject as? String)
    }

    @objc private func reasoningChanged() {
        onReasoningSelected(reasoningPopup.selectedItem?.representedObject as? String)
    }

    @objc private func closePressed() {
        onClose()
    }
}

@MainActor
private final class BubbleRowView: NSView {
    let textField = NSTextField(wrappingLabelWithString: " ")

    init(message: SpotifyCodexChatMessage) {
        super.init(frame: .zero)
        configure(message: message)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func configure(message: SpotifyCodexChatMessage) {
        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 18
        bubble.layer?.masksToBounds = true
        bubble.layer?.backgroundColor = message.role == .user
            ? NSColor.spotifyGreen.cgColor
            : NSColor.white.withAlphaComponent(0.09).cgColor
        bubble.layer?.borderColor = message.role == .user
            ? NSColor.clear.cgColor
            : NSColor.white.withAlphaComponent(0.08).cgColor
        bubble.layer?.borderWidth = message.role == .user ? 0 : 1
        bubble.translatesAutoresizingMaskIntoConstraints = false

        textField.stringValue = message.text.isEmpty ? " " : message.text
        textField.font = .systemFont(ofSize: 13, weight: .regular)
        textField.textColor = message.role == .user ? .black : .white.withAlphaComponent(0.92)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.maximumNumberOfLines = 0

        bubble.addSubview(textField)
        addSubview(bubble)

        let maxWidth: CGFloat = 322
        let leading: NSLayoutConstraint
        let trailing: NSLayoutConstraint
        var avatar: NSView?

        switch message.role {
        case .user:
            leading = bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 64)
            trailing = bubble.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        case .assistant:
            let assistantAvatar = AssistantAvatarView()
            assistantAvatar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(assistantAvatar)
            avatar = assistantAvatar
            leading = bubble.leadingAnchor.constraint(equalTo: assistantAvatar.trailingAnchor, constant: 8)
            trailing = bubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -58)
        }

        var constraints: [NSLayoutConstraint] = [
            leading,
            trailing,
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            textField.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            textField.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            textField.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
        ]

        if let avatar {
            constraints.append(contentsOf: [
                avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                avatar.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 2),
                avatar.widthAnchor.constraint(equalToConstant: 24),
                avatar.heightAnchor.constraint(equalToConstant: 24),
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }
}

@MainActor
private final class AssistantAvatarView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 1

        let mark = NSTextField(labelWithString: "C")
        mark.alignment = .center
        mark.font = .systemFont(ofSize: 11, weight: .bold)
        mark.textColor = .spotifyGreen
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor),
            mark.trailingAnchor.constraint(equalTo: trailingAnchor),
            mark.topAnchor.constraint(equalTo: topAnchor),
            mark.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private extension NSColor {
    static let spotifyGreen = NSColor(red: 0.12, green: 0.84, blue: 0.38, alpha: 1.0)
}

import AppKit
import SwiftUI

@MainActor
final class SpotifyCodexSidebarModel: ObservableObject {
    @Published var statusText: String = ""
    @Published var providerContext: String = ""
    @Published var isBusy: Bool = false
    @Published var messages: [SpotifyCodexChatMessage] = []
    @Published var draft: String = ""
    @Published var models: [SpotifyCodexModelOption] = []
    @Published var selectedModelID: String? = nil
    @Published var reasoning: [String] = []
    @Published var selectedReasoning: String? = nil
    @Published var focusComposerToken: Int = 0

    var onSend: (String) -> Void = { _ in }
    var onRefreshModels: () -> Void = {}
    var onModelSelected: (String?) -> Void = { _ in }
    var onReasoningSelected: (String?) -> Void = { _ in }
    var onResetChat: () -> Void = {}
    var onClose: () -> Void = {}
}

@MainActor
final class SpotifyCodexSidebarView: NSView {
    var onSend: (String) -> Void {
        get { model.onSend }
        set { model.onSend = newValue }
    }
    var onRefreshModels: () -> Void {
        get { model.onRefreshModels }
        set { model.onRefreshModels = newValue }
    }
    var onModelSelected: (String?) -> Void {
        get { model.onModelSelected }
        set { model.onModelSelected = newValue }
    }
    var onReasoningSelected: (String?) -> Void {
        get { model.onReasoningSelected }
        set { model.onReasoningSelected = newValue }
    }
    var onResetChat: () -> Void {
        get { model.onResetChat }
        set { model.onResetChat = newValue }
    }
    var onClose: () -> Void {
        get { model.onClose }
        set { model.onClose = newValue }
    }

    private let model = SpotifyCodexSidebarModel()
    private var hostingView: NSHostingView<SpotifyCodexSidebarRoot>!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func setCodexStatus(_ status: String) {
        model.statusText = sanitize(status)
    }

    func setProviderContext(_ context: String) {
        model.providerContext = context
    }

    func setBusy(_ busy: Bool) {
        model.isBusy = busy
    }

    func setModels(
        _ models: [SpotifyCodexModelOption],
        selectedModelID: String?,
        reasoning: [String],
        selectedReasoning: String?
    ) {
        model.models = models
        model.selectedModelID = selectedModelID
        model.reasoning = reasoning
        model.selectedReasoning = selectedReasoning
    }

    func appendMessage(_ message: SpotifyCodexChatMessage) {
        model.messages.append(message)
    }

    func updateMessage(id: UUID, text: String) {
        guard let index = model.messages.firstIndex(where: { $0.id == id }) else { return }
        model.messages[index].text = text
    }

    func clearMessages() {
        model.messages.removeAll()
    }

    func focusComposer() {
        model.focusComposerToken &+= 1
    }

    private func sanitize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("spotify.") || trimmed.contains("__bcu") {
            return ""
        }
        return trimmed
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        let inSelf = convert(point, from: superview)
        guard bounds.contains(inSelf) else { return nil }
        if let descendant = super.hitTest(point) {
            return descendant
        }
        return self
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let hosting = NSHostingView(rootView: SpotifyCodexSidebarRoot(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.hostingView = hosting
    }
}

struct SpotifyCodexSidebarRoot: View {
    @ObservedObject var model: SpotifyCodexSidebarModel
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        panel
            .preferredColorScheme(.dark)
            .onChange(of: model.focusComposerToken) { _, _ in
                isComposerFocused = true
            }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header
            messagesList
            composer
        }
        .background(Color.spotifyPanel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 24, x: -10, y: 8)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Spotify AI")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            iconButton(symbol: "square.and.pencil", help: "New chat", action: model.onResetChat)
            iconButton(symbol: "xmark", help: "Close", action: model.onClose)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func iconButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.spotifyTextSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(SpotifyHoverButtonStyle())
        .help(help)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.messages.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.top, 56)
                } else {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.messages, id: \.id) { message in
                            SpotifyCodexMessageRow(message: message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("__bottom__")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: model.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("__bottom__", anchor: .bottom)
                }
            }
            .onChange(of: model.messages.last?.text) { _, _ in
                proxy.scrollTo("__bottom__", anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .center, spacing: 14) {
            emptyHero
                .padding(.bottom, 4)
            Text(emptyHeadline)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(emptySub)
                .font(.system(size: 14))
                .foregroundStyle(Color.spotifyBodyText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var emptyHero: some View {
        let unavailable = model.statusText.lowercased().contains("unavailable")
            || model.statusText.lowercased().contains("disconnect")
        if unavailable {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(Color.spotifyTextSecondary)
        } else {
            Circle()
                .fill(Color.spotifyGreen)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.black)
                )
        }
    }

    private var emptyHeadline: String {
        let trimmed = model.statusText.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().contains("unavailable") { return "Spotify AI is unavailable" }
        if trimmed.lowercased().contains("connecting") { return "Connecting to Spotify AI" }
        return "Ask Spotify AI"
    }

    private var emptySub: String {
        let trimmed = model.statusText.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().contains("unavailable") {
            return "We couldn't reach Spotify AI right now. Try again in a moment."
        }
        if trimmed.lowercased().contains("connecting") {
            return "Hang tight — we're getting things ready."
        }
        return "Search for music, build a playlist, or ask anything about your library."
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                modelMenu
                effortMenu
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.spotifyPlaceholder)
                ZStack(alignment: .leading) {
                    if model.draft.isEmpty {
                        Text("Ask Spotify AI…")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.spotifyPlaceholder)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $model.draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .tint(Color.spotifyGreen)
                        .lineLimit(1...5)
                        .focused($isComposerFocused)
                        .onSubmit { send() }
                        .submitLabel(.send)
                }
                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.spotifySearchField)
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(canSend ? .black : Color.white.opacity(0.32))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(canSend ? Color.spotifyGreen : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .help("Send")
    }

    private var modelMenu: some View {
        Menu {
            if model.models.isEmpty {
                Text("No models loaded")
            } else {
                ForEach(model.models, id: \.id) { option in
                    Button(option.displayName) {
                        model.onModelSelected(option.id)
                    }
                }
                Divider()
                Button("Refresh") { model.onRefreshModels() }
            }
        } label: {
            spotifyChipLabel(text: modelLabel, isActive: model.selectedModelID != nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(.white)
    }

    private var modelLabel: String {
        if let id = model.selectedModelID,
           let option = model.models.first(where: { $0.id == id }) {
            return option.displayName
        }
        return "Model"
    }

    private var effortMenu: some View {
        Menu {
            if model.reasoning.isEmpty {
                Text("No effort levels")
            } else {
                ForEach(model.reasoning, id: \.self) { effort in
                    Button(effort.capitalized) {
                        model.onReasoningSelected(effort)
                    }
                }
            }
        } label: {
            spotifyChipLabel(text: effortLabel, isActive: model.selectedReasoning != nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .tint(.white)
    }

    private func spotifyChipLabel(text: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.white.opacity(0.68))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.68))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.spotifyCard, in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }

    private var effortLabel: String {
        if let value = model.selectedReasoning {
            return value.capitalized
        }
        return "Effort"
    }

    private var canSend: Bool {
        let trimmed = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !model.isBusy
    }

    private func send() {
        guard canSend else { return }
        let text = model.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        model.draft = ""
        model.onSend(text)
    }
}

private struct SpotifyHoverButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .onHover { hovering in
                isHovering = hovering
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed { return Color.white.opacity(0.16) }
        if isHovering { return Color.white.opacity(0.10) }
        return Color.clear
    }
}

private struct SpotifyCodexMessageRow: View {
    let message: SpotifyCodexChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.spotifyTextSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(message.text.isEmpty ? " " : message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch message.role {
        case .user:
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.86))
                )
        case .assistant:
            Circle()
                .fill(Color.spotifyGreen)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.black)
                )
        }
    }

    private var title: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return "Spotify AI"
        }
    }
}

private extension Color {
    // Spotify brand green.
    static let spotifyGreen = Color(red: 30 / 255, green: 215 / 255, blue: 96 / 255)
    static let spotifyAmber = Color(red: 1.0, green: 0.66, blue: 0.0)
    // Spotify panel surface (Your Library / Now Playing background) — #121212.
    static let spotifyPanel = Color(red: 0x12 / 255.0, green: 0x12 / 255.0, blue: 0x12 / 255.0)
    // Card / hover surface — #1f1f1f.
    static let spotifyCard = Color(red: 0x1f / 255.0, green: 0x1f / 255.0, blue: 0x1f / 255.0)
    // Heavier hover / pressed — #2a2a2a.
    static let spotifyHover = Color(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2a / 255.0)
    // Secondary / help text — #a7a7a7.
    static let spotifyTextSecondary = Color(red: 0xa7 / 255.0, green: 0xa7 / 255.0, blue: 0xa7 / 255.0)
    // Body / paragraph text — #b3b3b3.
    static let spotifyBodyText = Color(red: 0xb3 / 255.0, green: 0xb3 / 255.0, blue: 0xb3 / 255.0)
    // Placeholder text — matches Spotify's search bar "What do you want to play?".
    static let spotifyPlaceholder = Color.white.opacity(0.58)
    // Subtle text — #6a6a6a.
    static let spotifyTextMuted = Color(red: 0x6a / 255.0, green: 0x6a / 255.0, blue: 0x6a / 255.0)
    // Search field background — #2a2a2a.
    static let spotifySearchField = Color(red: 0x2a / 255.0, green: 0x2a / 255.0, blue: 0x2a / 255.0)
}

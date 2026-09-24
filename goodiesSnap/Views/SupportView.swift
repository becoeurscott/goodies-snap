import SwiftUI

struct SupportView: View {
    @EnvironmentObject var store: AppStore
    @State private var showChat = false
    @State private var expandedFAQ: String?

    private struct Topic: Identifiable {
        let id: String
        let icon: String
        let title: String
        let color: Color
    }

    private let topics: [Topic] = [
        Topic(id: "recipes", icon: "book.fill", title: "Recipes", color: .gsPeach),
        Topic(id: "subscription", icon: "crown.fill", title: "Subscription", color: Color(hex: 0xB48EF0)),
        Topic(id: "account", icon: "person.fill", title: "Account", color: Color(hex: 0x6EC6E6)),
        Topic(id: "importing", icon: "arrow.down.circle.fill", title: "Importing", color: Color(hex: 0xF0A58E)),
    ]

    private struct FAQ: Identifiable {
        let id: String
        let question: String
        let answer: String
    }

    private let faqs: [FAQ] = [
        FAQ(id: "save", question: "How do I save a recipe?",
            answer: "Tap the + button on the Home screen. You can paste a link, a YouTube video URL, type or paste text, or snap a photo of a dish. The AI reads it and creates a clean recipe card."),
        FAQ(id: "plan", question: "How does the meal planner work?",
            answer: "Open the Plan tab and tap a day to add recipes. Once you've planned your meals, the shopping list builds itself — sorted by aisle so you can shop without scrolling back."),
        FAQ(id: "cancel", question: "How do I cancel my subscription?",
            answer: "Open Settings on your iPhone → tap your name → Subscriptions → goodiesSnap → Cancel. Your recipes stay yours on any plan."),
        FAQ(id: "actions", question: "What are AI actions?",
            answer: "Every time goodiesSnap reads a link, photo or text to create a recipe card, it uses one AI action. Free accounts get 5 per month, Plus gets 100, and Pro gets 400."),
        FAQ(id: "delete", question: "How do I delete my account?",
            answer: "Go to Profile → Privacy & legal → Delete my account. This permanently removes your account and posts. Recipes saved on your device stay on your device."),
    ]

    var body: some View {
        if showChat {
            chatView
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else {
            helpView
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    // MARK: - Help / FAQ

    private var helpView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(title: "Chat support")

                Text("Related questions:")
                    .font(nunito(19, .extrabold))
                    .padding(.top, 28)

                // Topic cards grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(topics) { topic in
                        topicCard(topic)
                    }
                }
                .padding(.top, 14)

                Text("Frequently asked questions")
                    .font(nunito(19, .extrabold))
                    .padding(.top, 32)

                VStack(spacing: 0) {
                    ForEach(Array(faqs.enumerated()), id: \.element.id) { i, faq in
                        faqRow(faq, isLast: i == faqs.count - 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .glassCard(radius: 20, fill: 0.05, stroke: 0.1)
                .padding(.top, 14)

                Button {
                    openChat()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("Start a conversation")
                            .font(nunito(15, .extrabold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(DarkButtonStyle())
                .padding(.top, 24)

                Link(destination: Legal.support) {
                    Text("Or email us at contact@goodiessnap.com")
                        .font(nunito(12, .semibold))
                        .foregroundStyle(Color.fg(0.45))
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 12)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 44)
        }
    }

    private func topicCard(_ topic: Topic) -> some View {
        Button {
            openChat()
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(topic.color.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(topic.title)
                        .font(nunito(13.5, .extrabold))
                        .foregroundStyle(Color.gsFg)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.fg(0.35))
            }
            .padding(16)
            .background(topic.color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(topic.color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.97))
    }

    private func faqRow(_ faq: FAQ, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(AppStore.stepAnimation) {
                    expandedFAQ = expandedFAQ == faq.id ? nil : faq.id
                }
            } label: {
                HStack {
                    Text(faq.question)
                        .font(nunito(13.5, .bold))
                        .foregroundStyle(Color.gsFg)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 12)
                    Image(systemName: expandedFAQ == faq.id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.fg(0.4))
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedFAQ == faq.id {
                Text(faq.answer)
                    .font(nunito(12.5, .semibold))
                    .foregroundStyle(Color.fg(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !isLast {
                Rectangle().fill(Color.fg(0.07)).frame(height: 1)
            }
        }
    }

    // MARK: - Chat

    @State private var chatText = ""
    @State private var thread: [SupportAPI.Message] = []
    @State private var status = "ai"
    @State private var loading = false
    @State private var waitingForReply = false
    @State private var sendFailed = false

    private func openChat() {
        guard store.isAuthenticated else {
            store.showAuth(.support)
            return
        }
        withAnimation(AppStore.navAnimation) { showChat = true }
    }

    private var statusLine: (text: String, color: Color) {
        switch status {
        case "needs_human": return ("Waiting for our team", .orange)
        case "human": return ("Chatting with our team", .green)
        default: return ("AI assistant · our team can step in", .green)
        }
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            // Chat header
            HStack(spacing: 12) {
                Button {
                    withAnimation(AppStore.navAnimation) { showChat = false }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.gsFg)
                        .frame(width: 38, height: 38)
                        .background(Color.fg(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Chat support")
                        .font(nunito(16, .extrabold))
                    HStack(spacing: 5) {
                        Circle().fill(statusLine.color).frame(width: 7, height: 7)
                        Text(statusLine.text)
                            .font(nunito(11, .semibold))
                            .foregroundStyle(Color.fg(0.5))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.fg(0.08)).frame(height: 1)
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        welcomeBubble
                        ForEach(thread) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                        if waitingForReply {
                            typingBubble.id("typing")
                        }
                        if loading && thread.isEmpty {
                            ProgressView().padding(.top, 20)
                        }
                        if status == "needs_human" {
                            banner("A person from our team will reply here. You can close the app — the answer will be waiting.")
                        } else if status == "closed" {
                            banner("This conversation is closed. Send a message to start a new one.")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
                .onChange(of: thread.count) { _, _ in scrollToEnd(proxy) }
                .onChange(of: waitingForReply) { _, _ in scrollToEnd(proxy) }
            }

            if sendFailed {
                Text("Couldn't send. Check your connection and try again.")
                    .font(nunito(12, .semibold))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .padding(.top, 8)
            }

            // Input bar
            HStack(spacing: 10) {
                TextField("Your question", text: $chatText, axis: .vertical)
                    .font(nunito(14, .semibold))
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.fg(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.fg(0.12), lineWidth: 1)
                    )

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(canSend ? Color.gsPeach : Color.fg(0.2))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.fg(0.08)).frame(height: 1)
            }
        }
        .task { await loadThread() }
        // While the team owns the conversation, look for their reply every few seconds.
        // `.task(id:)` cancels the loop when the status changes or the chat closes.
        .task(id: status) {
            guard status == "needs_human" || status == "human" else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                await pollNewMessages()
            }
        }
    }

    private var canSend: Bool {
        !waitingForReply && !chatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation {
            if waitingForReply {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = thread.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var welcomeBubble: some View {
        botRow(label: nil) {
            Text("Hello! 👋 I'm the goodiesSnap assistant. Ask me anything about the app, your plan or your recipes — and if you'd rather talk to a person, just say so.")
        }
    }

    private var typingBubble: some View {
        botRow(label: nil) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Typing…").foregroundStyle(Color.fg(0.5))
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(nunito(12, .semibold))
            .foregroundStyle(Color.fg(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.fg(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 4)
    }

    private func botRow<Content: View>(label: String?, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: label == nil ? "sparkles" : "person.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(label == nil ? Color.gsPeach : Color.gsDock)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                if let label {
                    Text(label)
                        .font(nunito(10.5, .extrabold))
                        .foregroundStyle(Color.fg(0.5))
                }
                content()
                    .font(nunito(13.5, .semibold))
                    .foregroundStyle(Color.gsFg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.fg(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(maxWidth: 280, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    @ViewBuilder
    private func chatBubble(_ msg: SupportAPI.Message) -> some View {
        let time = msg.date.map { Self.timeFormatter.string(from: $0) } ?? ""
        if msg.isMine {
            VStack(alignment: .trailing, spacing: 4) {
                Text(msg.body)
                    .font(nunito(13.5, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.gsDock)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(time)
                    .font(nunito(10, .semibold))
                    .foregroundStyle(Color.fg(0.35))
            }
            .frame(maxWidth: 280, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                botRow(label: msg.sender == "agent" ? "\(msg.authorName ?? "goodiesSnap team") · goodiesSnap team" : nil) {
                    Text(msg.body)
                }
                Text(time)
                    .font(nunito(10, .semibold))
                    .foregroundStyle(Color.fg(0.35))
                    .padding(.leading, 40)
            }
        }
    }

    /// Runs a support call with the current token, renewing it once if it has expired.
    private func withToken(_ op: (String) async throws -> SupportAPI.Thread) async throws -> SupportAPI.Thread {
        guard let token = store.aiToken else { throw SupportAPI.SupportError.notSignedIn }
        do {
            return try await op(token)
        } catch SupportAPI.SupportError.notSignedIn {
            guard let fresh = await store.refreshAIToken?() else { throw SupportAPI.SupportError.notSignedIn }
            store.aiToken = fresh
            return try await op(fresh)
        }
    }

    private func loadThread() async {
        loading = true
        defer { loading = false }
        guard let result = try? await withToken({ try await SupportAPI.history(token: $0) }) else { return }
        thread = result.messages
        status = result.conversation?.status ?? "ai"
    }

    private func pollNewMessages() async {
        guard let result = try? await withToken({ try await SupportAPI.history(after: thread.last?.createdAt, token: $0) }) else { return }
        merge(result.messages)
        if let s = result.conversation?.status { status = s }
    }

    /// Adds messages not already shown; the server can resend the newest one.
    private func merge(_ incoming: [SupportAPI.Message]) {
        let known = Set(thread.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }
        if !fresh.isEmpty { thread.append(contentsOf: fresh) }
    }

    private func sendMessage() {
        let text = chatText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !waitingForReply else { return }
        chatText = ""
        sendFailed = false
        Haptics.tap(.light)
        // Only show "typing" when the assistant is the one who'll answer.
        waitingForReply = true

        Task {
            defer { waitingForReply = false }
            do {
                let result = try await withToken { try await SupportAPI.send(text, token: $0) }
                if status == "closed" { thread = [] }
                merge(result.messages)
                if let s = result.conversation?.status { status = s }
            } catch SupportAPI.SupportError.notSignedIn {
                chatText = text
                store.showAuth(.support)
            } catch {
                chatText = text
                sendFailed = true
            }
        }
    }

    // MARK: - Shared header

    private func header(title: String) -> some View {
        HStack(spacing: 12) {
            Button { store.goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 42, height: 42)
                    .background(Color.fg(0.06))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.fg(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "headphones")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(nunito(15, .extrabold))
            }
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
    }
}

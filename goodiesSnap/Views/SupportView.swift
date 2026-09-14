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
                    withAnimation(AppStore.navAnimation) { showChat = true }
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
                    Text("Or email us at support@goodiessnap.app")
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
            withAnimation(AppStore.navAnimation) { showChat = true }
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

    private struct ChatMessage: Identifiable {
        let id = UUID()
        let text: String
        let isBot: Bool
        let time: String
    }

    @State private var chatText = ""
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Hello! 👋 I'm here to help with goodiesSnap. Send me a message to start chatting.", isBot: true, time: "now")
    ]

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
                        Circle().fill(Color.green).frame(width: 7, height: 7)
                        Text("Online")
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
                        ForEach(messages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
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
                        .foregroundStyle(chatText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.fg(0.2) : Color.gsPeach)
                }
                .buttonStyle(.plain)
                .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.fg(0.08)).frame(height: 1)
            }
        }
    }

    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if msg.isBot {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.gsPeach)
                    .clipShape(Circle())
            }

            VStack(alignment: msg.isBot ? .leading : .trailing, spacing: 4) {
                Text(msg.text)
                    .font(nunito(13.5, .semibold))
                    .foregroundStyle(msg.isBot ? Color.gsFg : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(msg.isBot ? Color.fg(0.06) : Color.gsDock)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(msg.time)
                    .font(nunito(10, .semibold))
                    .foregroundStyle(Color.fg(0.35))
            }
            .frame(maxWidth: 280, alignment: msg.isBot ? .leading : .trailing)

            if !msg.isBot {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.isBot ? .leading : .trailing)
    }

    private func sendMessage() {
        let text = chatText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let time = formatter.string(from: Date())

        messages.append(ChatMessage(text: text, isBot: false, time: time))
        chatText = ""
        Haptics.tap(.light)

        Task {
            try? await Task.sleep(for: .seconds(1.2))
            let reply = autoReply(for: text)
            messages.append(ChatMessage(text: reply, isBot: true, time: formatter.string(from: Date())))
        }
    }

    private func autoReply(for question: String) -> String {
        let q = question.lowercased()
        if q.contains("cancel") || q.contains("subscription") {
            return "To manage or cancel your subscription, go to Settings → your name → Subscriptions → goodiesSnap on your iPhone. Your saved recipes stay yours on any plan."
        }
        if q.contains("delete") || q.contains("account") {
            return "You can delete your account from Profile → Privacy & legal → Delete my account. This is permanent and removes your posts and comments, but recipes on your device stay."
        }
        if q.contains("save") || q.contains("recipe") || q.contains("import") {
            return "Tap the + button on the Home screen to save a recipe. You can paste a web link, YouTube URL, type text, or snap a photo — the AI creates a clean recipe card for you."
        }
        if q.contains("plan") || q.contains("meal") || q.contains("shopping") {
            return "Open the Plan tab to drop recipes onto your week. Once planned, the shopping list builds itself, sorted by aisle. Head to the Shopping tab to check items off."
        }
        if q.contains("ai") || q.contains("action") || q.contains("limit") {
            return "AI actions are used each time goodiesSnap reads a link, photo or text to create a recipe. Free: 5/month, Plus: 100/month, Pro: 400/month. Upgrade in Profile → Upgrade to Pro."
        }
        return "Thanks for reaching out! For detailed help, email us at support@goodiessnap.app and we'll get back to you shortly. 💛"
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

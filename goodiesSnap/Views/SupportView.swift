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
                    .foregroundStyle(Color.gsFg)
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
    @State private var sending = false
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "Hey! 👋 I'm your goodiesSnap assistant. Ask me anything about recipes, subscriptions, meal planning, or how things work in the app.", isBot: true, time: "now")
    ]

    private var chatView: some View {
        VStack(spacing: 0) {
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

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                        if sending {
                            typingIndicator
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
                        .foregroundStyle(chatText.trimmingCharacters(in: .whitespaces).isEmpty || sending ? Color.fg(0.2) : Color.gsPeach)
                }
                .buttonStyle(.plain)
                .disabled(chatText.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.fg(0.08)).frame(height: 1)
            }
        }
    }

    private var typingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.gsPeach)
                .clipShape(Circle())

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.fg(0.3))
                        .frame(width: 6, height: 6)
                        .opacity(0.4)
                        .animation(
                            .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: sending
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.fg(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        guard !text.isEmpty, !sending else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let time = formatter.string(from: Date())

        messages.append(ChatMessage(text: text, isBot: false, time: time))
        chatText = ""
        sending = true
        Haptics.tap(.light)

        Task {
            let reply = await callSupportAI()
            sending = false
            messages.append(ChatMessage(text: reply, isBot: true, time: formatter.string(from: Date())))
        }
    }

    // MARK: - Claude AI support

    private static let supportSystemPrompt = """
    You are the goodiesSnap support assistant — a friendly, helpful AI built into the goodiesSnap iOS recipe app.

    About the app:
    - goodiesSnap lets users save recipes from links, YouTube videos, photos, or typed text using AI
    - The AI reads the input and creates a clean recipe card with ingredients, steps, cook time, and nutrition
    - Users can plan meals for the week by dropping recipes onto days in the Plan tab
    - The shopping list builds itself from planned meals, sorted by aisle
    - Users can discover recipes in the Discover tab (browse by cuisine, food type, cook time, calories)
    - The Community tab shows a TikTok-style reel feed where users share food posts
    - Recipes can be cooked step-by-step with built-in timers (Cook mode)

    Features:
    - Save recipe: tap + on Home → paste link, YouTube URL, type text, or snap a photo
    - Meal planner: Plan tab → tap a day → add recipes → shopping list auto-generates
    - Shopping list: Shopping tab → check off items as you shop
    - Discover: browse 700+ recipes by cuisine, food type, cook time, calories
    - Community: vertical reel feed of food posts from other users
    - Cook mode: step-by-step cooking with timers, hands-free
    - Profile: edit name, view stats, manage subscription

    Subscription plans:
    - Free: 5 AI actions per month
    - Plus: 100 AI actions per month
    - Pro: 400 AI actions per month
    - AI actions are consumed when importing a recipe (reading a link/photo/text)
    - To cancel: iPhone Settings → your name → Subscriptions → goodiesSnap

    Account:
    - Sign in with email/password or Google
    - Disconnect (sign out): Profile → bottom of screen → Disconnect (signs out, keeps account)
    - Delete account: Profile → Privacy & legal → Delete my account (permanent, removes posts/comments)
    - Recipes saved on the device stay on the device even after deletion

    Rules:
    - Keep answers short (2-4 sentences max), warm, and helpful
    - Use simple language, no technical jargon
    - If you don't know something specific, suggest emailing contact@goodiessnap.com
    - Never make up features that don't exist
    - Never ask for passwords, payment info, or personal data
    - You can use one emoji per reply max
    """

    private func callSupportAI() async -> String {
        let key = store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return "I'm not able to connect right now. For help, email us at contact@goodiessnap.com 💛"
        }

        let provider = RecipeExtractor.Provider.forKey(key)
        let history: [[String: Any]] = messages.compactMap { msg in
            guard msg.text != messages.first?.text else { return nil }
            return ["role": msg.isBot ? "assistant" : "user", "content": msg.text]
        }

        var request: URLRequest
        var body: [String: Any]

        switch provider {
        case .anthropic:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 300,
                "system": Self.supportSystemPrompt,
                "messages": history,
            ]

        case .openRouter:
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("https://goodiessnap.app", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("goodiesSnap", forHTTPHeaderField: "X-Title")
            body = [
                "model": "anthropic/claude-haiku-4-5-20251001",
                "max_tokens": 300,
                "messages": [["role": "system", "content": Self.supportSystemPrompt]] + history,
            ]
        }

        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Something went wrong. Try again or email contact@goodiessnap.com 💛"
            }

            switch provider {
            case .anthropic:
                if let content = json["content"] as? [[String: Any]],
                   let text = content.first?["text"] as? String {
                    return text
                }
            case .openRouter:
                if let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let text = message["content"] as? String {
                    return text
                }
            }

            return "I couldn't process that. Try rephrasing or email contact@goodiessnap.com 💛"
        } catch {
            return "Connection issue — check your internet and try again, or email contact@goodiessnap.com 💛"
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

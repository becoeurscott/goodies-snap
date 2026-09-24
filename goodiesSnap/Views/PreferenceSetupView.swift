import SwiftUI

struct PreferenceSetupView: View {
    @EnvironmentObject var store: AppStore

    private enum Step: Int, CaseIterable {
        case motivation, cuisine, frequency, household, priorities, store_, mealPlan

        var eyebrow: String {
            switch self {
            case .motivation: return "Goals"
            case .cuisine: return "Cuisine"
            case .frequency: return "Frequency"
            case .household: return "Household"
            case .priorities: return "Priorities"
            case .store_: return "Store"
            case .mealPlan: return "Meal plan"
            }
        }

        var title: String {
            switch self {
            case .motivation: return "What brings you to Goodies Snap?"
            case .cuisine: return "How do you like to eat?"
            case .frequency: return "How often do you cook?"
            case .household: return "Who are you cooking for?"
            case .priorities: return "What matters most when you choose a recipe?"
            case .store_: return "Where do you shop?"
            case .mealPlan: return "What should we help you plan?"
            }
        }

        var subtitle: String {
            switch self {
            case .motivation: return "Pick all that apply."
            case .cuisine: return "We'll use this to personalize your feed."
            case .frequency: return "No judgment, just better recommendations."
            case .household: return "Portions and meal plans adjust to fit."
            case .priorities: return "Pick up to 3 things that matter most."
            case .store_: return "We'll tailor prices and availability."
            case .mealPlan: return "We'll build your weekly plan around this."
            }
        }
    }

    @State private var showReveal = false
    @State private var direction: Int = 1

    private var step: Step {
        Step(rawValue: max(0, min(store.preferenceIndex, Step.allCases.count - 1))) ?? .motivation
    }

    private var isLast: Bool { step == Step.allCases.last }

    private var canContinue: Bool {
        switch step {
        case .motivation: return !store.preferences.motivations.isEmpty
        case .cuisine: return !store.preferences.cuisines.isEmpty
        case .frequency: return !store.preferences.cookFrequency.isEmpty
        case .household: return !store.preferences.householdSize.isEmpty
        case .priorities: return !store.preferences.priorities.isEmpty
        case .store_: return !store.preferences.preferredStore.isEmpty
        case .mealPlan: return !store.preferences.mealPlanStyle.isEmpty
        }
    }

    var body: some View {
        ZStack {
            Color.gsBg.ignoresSafeArea()

            if showReveal {
                revealScreen
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    topBar

                    Spacer(minLength: 12)

                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.title)
                                .font(nunito(24, .black))
                                .lineSpacing(1)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(step.subtitle)
                                .font(nunito(13, .semibold))
                                .foregroundStyle(Color.gsMuted)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        content
                            .padding(.top, 14)
                    }
                    .id(store.preferenceIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)
                    ))

                    Spacer(minLength: 10)

                    Button { goForward() } label: {
                        HStack(spacing: 8) {
                            Text(isLast ? "See my taste profile" : "Continue")
                                .font(nunito(15, .extrabold))
                            Image(systemName: isLast ? "sparkles" : "chevron.right")
                                .font(.system(size: 12, weight: .black))
                        }
                        .foregroundStyle(Color.gsFg)
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(DarkButtonStyle())
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.45)
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: store.preferenceIndex)
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: showReveal)
    }

    // MARK: - Page turns

    private func goForward() {
        guard canContinue else { return }
        guard !isLast else {
            withAnimation { showReveal = true }
            PreferenceSound.success()
            Haptics.notify(.success)
            return
        }
        direction = 1
        store.preferenceNext(maxIndex: Step.allCases.count - 1)
    }

    private func goBack() {
        guard store.preferenceIndex > 0 else { return }
        direction = -1
        store.preferenceBack()
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { goBack() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color.gsFg)
                    .frame(width: 42, height: 42)
                    .background(Color.gsFill)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(store.preferenceIndex > 0 ? 1 : 0)
            .disabled(store.preferenceIndex == 0)

            HStack(spacing: 5) {
                ForEach(Step.allCases.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= store.preferenceIndex ? Color.gsPeach : Color.gsFill)
                        .frame(height: 5)
                        .frame(maxWidth: .infinity)
                        .animation(AppStore.stepAnimation, value: store.preferenceIndex)
                }
            }

            Button { store.askForAccount() } label: {
                Text("Skip")
                    .font(nunito(13, .bold))
                    .foregroundStyle(Color.gsMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .motivation:
            multiSelectGrid(
                items: Self.motivations,
                selected: store.preferences.motivations
            ) { value in
                store.answerPreference { prefs in
                    if prefs.motivations.contains(value) {
                        prefs.motivations.removeAll { $0 == value }
                    } else {
                        prefs.motivations.append(value)
                    }
                }
            }

        case .cuisine:
            emojiTileGrid(
                items: Self.cuisines,
                selected: Set(store.preferences.cuisines)
            ) { value in
                store.answerPreference { prefs in
                    if prefs.cuisines.contains(value) {
                        prefs.cuisines.removeAll { $0 == value }
                    } else {
                        prefs.cuisines.append(value)
                    }
                }
            }

        case .frequency:
            singleSelectGrid(
                items: Self.frequencies,
                selected: store.preferences.cookFrequency
            ) { value in
                store.answerPreference { $0.cookFrequency = value }
            }

        case .household:
            singleSelectGrid(
                items: Self.households,
                selected: store.preferences.householdSize
            ) { value in
                store.answerPreference { $0.householdSize = value }
            }

        case .priorities:
            multiSelectGrid(
                items: Self.priorityOptions,
                selected: store.preferences.priorities,
                maxSelections: 3
            ) { value in
                store.answerPreference { prefs in
                    if prefs.priorities.contains(value) {
                        prefs.priorities.removeAll { $0 == value }
                    } else if prefs.priorities.count < 3 {
                        prefs.priorities.append(value)
                    } else {
                        Haptics.notify(.warning)
                    }
                }
            }

        case .store_:
            singleSelectGrid(
                items: Self.stores,
                selected: store.preferences.preferredStore
            ) { value in
                store.answerPreference { $0.preferredStore = value }
            }

        case .mealPlan:
            multiSelectGrid(
                items: Self.mealPlanOptions,
                selected: store.preferences.mealPlanStyle
            ) { value in
                store.answerPreference { prefs in
                    if prefs.mealPlanStyle.contains(value) {
                        prefs.mealPlanStyle.removeAll { $0 == value }
                    } else {
                        prefs.mealPlanStyle.append(value)
                    }
                }
            }
        }
    }

    // MARK: - Reveal screen

    private var revealScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            Text("Your taste profile")
                .font(nunito(32, .black))
                .stagger(0)

            Text("Here's what we learned about you.")
                .font(nunito(14.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .padding(.top, 6)
                .stagger(1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    revealRow("Goals", items: store.preferences.motivations, stagger: 2)
                    revealRow("Cuisines", items: store.preferences.cuisines, stagger: 3)
                    revealRow("Cooking", items: [store.preferences.cookFrequency], stagger: 4)
                    revealRow("Household", items: [store.preferences.householdSize], stagger: 5)
                    revealRow("Priorities", items: store.preferences.priorities, stagger: 6)
                    revealRow("Store", items: [store.preferences.preferredStore], stagger: 7)
                    revealRow("Planning", items: store.preferences.mealPlanStyle, stagger: 8)
                }
                .padding(.top, 28)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 20)

            Button {
                store.preferenceNext(maxIndex: Step.allCases.count - 1)
            } label: {
                HStack(spacing: 8) {
                    Text("Let's cook")
                        .font(nunito(15, .extrabold))
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                }
                .foregroundStyle(Color.gsFg)
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(DarkButtonStyle())
            .padding(.bottom, 28)
            .stagger(9)
        }
        .padding(.horizontal, 24)
    }

    private func revealRow(_ label: String, items: [String], stagger idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(nunito(11, .extrabold))
                .foregroundStyle(Color.gsMuted)
                .kerning(0.8)

            FlowLayout(spacing: 8) {
                ForEach(items.filter { !$0.isEmpty }, id: \.self) { item in
                    HStack(spacing: 6) {
                        Text(Self.emoji(for: item))
                            .font(.system(size: 16))
                        Text(item)
                            .font(nunito(13.5, .bold))
                            .foregroundStyle(Color.gsFg)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gsPeachSoft)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.gsCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .stagger(idx)
    }

    // MARK: - Reusable grids

    private func multiSelectGrid(items: [(String, String)], selected: [String],
                                 maxSelections: Int = .max,
                                 action: @escaping (String) -> Void) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.0) { i, pair in
                let (value, _) = pair
                let isSel = selected.contains(value)
                PreferenceChip(
                    emoji: Self.emoji(for: value),
                    title: value,
                    selected: isSel
                ) { action(value) }
                .stagger(3 + i)
            }
        }
    }

    private func singleSelectGrid(items: [(String, String)], selected: String,
                                  action: @escaping (String) -> Void) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.0) { i, pair in
                let (value, _) = pair
                PreferenceChip(
                    emoji: Self.emoji(for: value),
                    title: value,
                    selected: selected == value
                ) { action(value) }
                .stagger(3 + i)
            }
        }
    }

    private func emojiTileGrid(items: [(String, String)], selected: Set<String>,
                               action: @escaping (String) -> Void) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.0) { i, pair in
                let (value, _) = pair
                let isSel = selected.contains(value)
                Button { action(value) } label: {
                    VStack(spacing: 3) {
                        Text(Self.emoji(for: value)).font(.system(size: 22))
                        Text(value)
                            .font(nunito(11.5, .extrabold))
                            .foregroundStyle(Color.gsFg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(isSel ? Color.gsPeachSoft : Color.gsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSel ? Color.gsPeach : Color.clear, lineWidth: 2))
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .stagger(3 + i)
            }
        }
    }

    // MARK: - Data

    static let motivations: [(String, String)] = [
        ("Find recipes to cook", "Browse and save dishes you'll love"),
        ("Plan my meals for the week", "Stay organized and eat better"),
        ("Plan my grocery shopping", "Build smarter shopping lists"),
        ("Eat healthier", "Nutrition-forward picks"),
        ("Learn to cook", "Step-by-step guidance for beginners"),
        ("Discover food from around the world", "Explore global flavors"),
        ("Control how much I spend", "Budget-friendly meals"),
    ]

    static let cuisines: [(String, String)] = [
        ("Italian", ""), ("Mexican", ""), ("Asian", ""), ("American", ""),
        ("Mediterranean", ""), ("Indian", ""), ("French", ""), ("Middle Eastern", ""),
        ("African", ""), ("Show me everything", ""),
    ]

    static let frequencies: [(String, String)] = [
        ("Every day", "I'm always in the kitchen"),
        ("A few times a week", "I cook more than I eat out"),
        ("A couple times a week", "Mix of cooking and takeout"),
        ("Once a week or less", "I cook when I'm feeling it"),
        ("Mostly takeout", "But I want to cook more"),
    ]

    static let households: [(String, String)] = [
        ("Just me", "Solo portions"),
        ("2 people", "Cooking for two"),
        ("3-4 people", "Family-sized meals"),
        ("5+ people", "Big batch cooking"),
        ("It varies", "Flexible portions"),
    ]

    static let priorityOptions: [(String, String)] = [
        ("Quick to make", "30 minutes or less"),
        ("Affordable", "Budget-friendly ingredients"),
        ("Healthy", "Balanced and nutritious"),
        ("Easy to follow", "Simple steps, few surprises"),
        ("Something new", "Recipes I haven't tried"),
        ("High protein", "Filling, muscle-friendly meals"),
        ("Good for the whole family", "Crowd-pleasers"),
        ("Great for meal prep", "Make ahead and store"),
    ]

    static let stores: [(String, String)] = [
        ("Walmart", ""),
        ("Kroger", ""),
        ("Costco", ""),
        ("Whole Foods", ""),
        ("Target", ""),
        ("Trader Joe's", ""),
        ("Aldi", ""),
        ("Wherever is closest", ""),
    ]

    static let mealPlanOptions: [(String, String)] = [
        ("Weeknight dinners", "Quick meals for busy evenings"),
        ("Full week of meals", "Breakfast, lunch, and dinner"),
        ("Lunches to bring to work", "Packable and reheatable"),
        ("Snacks and sides", "In-between bites"),
        ("Meal prep Sundays", "Cook once, eat all week"),
        ("Date night at home", "Something a little special"),
        ("Cooking with kids", "Fun and simple together"),
        ("I'll figure it out myself", "Just show me great recipes"),
    ]

    // MARK: - Emoji map

    static func emoji(for value: String) -> String {
        switch value {
        case "Find recipes to cook": return "🍽️"
        case "Plan my meals for the week": return "📅"
        case "Plan my grocery shopping": return "🛒"
        case "Eat healthier": return "🥗"
        case "Learn to cook": return "👨‍🍳"
        case "Discover food from around the world": return "🌍"
        case "Control how much I spend": return "💰"

        case "Italian": return "🍝"
        case "Mexican": return "🌮"
        case "Asian": return "🥢"
        case "American": return "🍔"
        case "Mediterranean": return "🫒"
        case "Indian": return "🍛"
        case "French": return "🥐"
        case "Middle Eastern": return "🧆"
        case "African": return "🍲"
        case "Show me everything": return "✨"

        case "Every day": return "🔥"
        case "A few times a week": return "🍳"
        case "A couple times a week": return "🍴"
        case "Once a week or less": return "🙂"
        case "Mostly takeout": return "📦"

        case "Just me": return "🙋"
        case "2 people": return "👫"
        case "3-4 people": return "👨‍👩‍👧"
        case "5+ people": return "👨‍👩‍👧‍👦"
        case "It varies": return "🔄"

        case "Quick to make": return "⚡️"
        case "Affordable": return "💸"
        case "Healthy": return "🥦"
        case "Easy to follow": return "📖"
        case "Something new": return "🆕"
        case "High protein": return "🍗"
        case "Good for the whole family": return "👨‍👩‍👧‍👦"
        case "Great for meal prep": return "🍱"

        case "Walmart": return "🏬"
        case "Kroger": return "🛒"
        case "Costco": return "📦"
        case "Whole Foods": return "🌿"
        case "Target": return "🎯"
        case "Trader Joe's": return "🌻"
        case "Aldi": return "💰"
        case "Wherever is closest": return "📍"

        case "Weeknight dinners": return "🌙"
        case "Full week of meals": return "📋"
        case "Lunches to bring to work": return "🥪"
        case "Snacks and sides": return "🍿"
        case "Meal prep Sundays": return "🗓️"
        case "Date night at home": return "🕯️"
        case "Cooking with kids": return "👶"
        case "I'll figure it out myself": return "🤷"

        default: return "🍴"
        }
    }
}

// MARK: - Shared components

private struct PreferenceChip: View {
    let emoji: String
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
                    .background(selected ? Color.white.opacity(0.7) : Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text(title)
                    .font(nunito(14, .extrabold))
                    .foregroundStyle(Color.gsFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.gsAccentInk)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? Color.gsPeachSoft : Color.gsCard)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(selected ? Color.gsPeach : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.975))
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct Stagger: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(x: shown ? 0 : 46)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(
                    .spring(response: 0.62, dampingFraction: 0.86)
                        .delay(Double(index) * 0.12)
                ) { shown = true }
            }
    }
}

private extension View {
    func stagger(_ index: Int) -> some View { modifier(Stagger(index: index)) }
}

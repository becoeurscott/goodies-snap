import SwiftUI

struct PreferenceSetupView: View {
    @EnvironmentObject var store: AppStore

    private enum Step: Int, CaseIterable {
        case goal, diet, avoid, time, servings, skill

        var eyebrow: String {
            switch self {
            case .goal: return "Goal"
            case .diet: return "Food style"
            case .avoid: return "Avoid"
            case .time: return "Time"
            case .servings: return "Household"
            case .skill: return "Cooking level"
            }
        }

        var title: String {
            switch self {
            case .goal: return "What should Goodies Snap help with first?"
            case .diet: return "What kind of recipes should we favor?"
            case .avoid: return "Anything we should avoid?"
            case .time: return "How much time do you usually have?"
            case .servings: return "How many people do you cook for?"
            case .skill: return "How confident are you in the kitchen?"
            }
        }

        var subtitle: String {
            switch self {
            case .goal: return "This tunes your home picks and recipe suggestions."
            case .diet: return "You can still save any recipe later."
            case .avoid: return "Pick all that apply, or choose none."
            case .time: return "We will push faster recipes when your night is tight."
            case .servings: return "Meal plans and recipe cards will feel closer to real life."
            case .skill: return "Cook mode can lean simpler or more adventurous."
            }
        }
    }

    /// Live horizontal travel of the page under the finger.
    @State private var dragX: CGFloat = 0
    @State private var pageWidth: CGFloat = 400
    /// True while a committed page turn is playing, so a second swipe can't interleave.
    @State private var turning = false
    /// The time slider drags horizontally too; without this a slide would also turn the page.
    @State private var adjustingSlider = false

    private var step: Step {
        Step(rawValue: max(0, min(store.preferenceIndex, Step.allCases.count - 1))) ?? .goal
    }

    private var isLast: Bool { step == Step.allCases.last }

    private var canContinue: Bool {
        switch step {
        case .goal: return !store.preferences.goal.isEmpty
        case .diet: return !store.preferences.diet.isEmpty
        case .avoid: return true
        case .time, .servings: return true
        case .skill: return !store.preferences.skill.isEmpty
        }
    }

    var body: some View {
        ZStack {
            Color.gsBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar

                Spacer(minLength: 24)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.title)
                            .font(nunito(30, .black))
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .stagger(0)

                        Text(step.subtitle)
                            .font(nunito(14, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .stagger(1)
                    }

                    content
                        .padding(.top, 24)
                }
                // Re-keying on the step is what gives each question its own entrance. The
                // page itself is moved by `dragX` rather than by a transition, so a swipe
                // tracks the finger continuously instead of jumping on release.
                .id(store.preferenceIndex)
                .offset(x: dragX)
                .opacity(1 - min(abs(dragX) / (pageWidth * 0.9), 0.7))

                Spacer(minLength: 24)

                Button { goForward() } label: {
                    HStack(spacing: 8) {
                        Text(isLast ? "Save my taste profile" : "Continue")
                            .font(nunito(15, .extrabold))
                        Image(systemName: isLast ? "checkmark" : "chevron.right")
                            .font(.system(size: 12, weight: .black))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(DarkButtonStyle())
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.45)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
        .animation(AppStore.stepAnimation, value: store.preferenceIndex)
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { pageWidth = geo.size.width }
            }
        )
        // The questions read like pages, so they turn like pages: the page follows the
        // finger, and only commits past a threshold. Forward is gated on the question being
        // answered, matching the Continue button; blocked drags rubber-band instead.
        .simultaneousGesture(
            DragGesture(minimumDistance: 14)
                .onChanged { value in
                    guard !turning, !adjustingSlider else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let raw = value.translation.width
                    let blocked = (raw < 0 && !canContinue) || (raw > 0 && store.preferenceIndex == 0)
                    dragX = blocked ? raw * 0.2 : raw
                }
                .onEnded { value in
                    guard !turning, !adjustingSlider else { dragX = 0; return }
                    let dx = value.translation.width
                    let flick = value.predictedEndTranslation.width
                    let forward = dx < -70 || flick < -190
                    let back = dx > 70 || flick > 190
                    if forward, canContinue {
                        goForward()
                    } else if back, store.preferenceIndex > 0 {
                        goBack()
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { dragX = 0 }
                    }
                }
        )
    }

    // MARK: - Page turns

    private func goForward() {
        guard canContinue, !turning else { return }
        // The last step leaves the flow entirely, so there is no page to turn.
        guard !isLast else {
            dragX = 0
            store.preferenceNext(maxIndex: Step.allCases.count - 1)
            return
        }
        turn(to: -1) { store.preferenceNext(maxIndex: Step.allCases.count - 1) }
    }

    private func goBack() {
        guard store.preferenceIndex > 0, !turning else { return }
        turn(to: 1) { store.preferenceBack() }
    }

    /// Throws the current page off `direction`, swaps the question while it is off-screen,
    /// then springs the next one in from the opposite edge — one continuous movement.
    private func turn(to direction: CGFloat, _ change: @escaping () -> Void) {
        turning = true
        let travel = pageWidth * 1.05
        // Carry on from wherever the finger left off rather than restarting the motion.
        let remaining = max(0.10, min(0.20, Double((travel - abs(dragX)) / travel) * 0.20))
        withAnimation(.easeOut(duration: remaining)) { dragX = direction * travel }

        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                change()
                dragX = -direction * travel   // place the incoming page just off the far edge
            }
            withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) { dragX = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) { turning = false }
        }
    }

    /// Back button + a top progress bar (segments fill as you advance), like the reference.
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

            HStack(spacing: 6) {
                ForEach(Step.allCases.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= store.preferenceIndex ? Color.gsPeach : Color.gsFill)
                        .frame(height: 6)
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

    @ViewBuilder
    private var content: some View {
        switch step {
        case .goal:
            optionGrid(["Eat healthier", "Save time", "Meal prep", "Try new food"], selected: store.preferences.goal) { value in
                store.answerPreference { $0.goal = value }
            }
        case .diet:
            // A 2-column emoji tile grid, matching the reference's diet picker.
            emojiTileGrid(["Anything", "Vegetarian", "High protein", "Low carb", "Mediterranean"],
                          selected: store.preferences.diet) { value in
                store.answerPreference { $0.diet = value }
            }
        case .avoid:
            VStack(spacing: 10) {
                ForEach(Array(["Peanuts", "Dairy", "Shellfish", "Gluten", "Pork"].enumerated()), id: \.element) { i, value in
                    PreferenceOption(
                        emoji: Self.emoji(for: value),
                        title: value,
                        subtitle: store.preferences.avoid.contains(value) ? "We'll keep this out of top picks" : "Tap to avoid",
                        selected: store.preferences.avoid.contains(value)
                    ) {
                        store.answerPreference { prefs in
                            if prefs.avoid.contains(value) {
                                prefs.avoid.removeAll { $0 == value }
                            } else {
                                prefs.avoid.append(value)
                            }
                        }
                    }
                    .stagger(3 + i)
                }
            }
        case .time:
            VStack(spacing: 18) {
                Text("\(store.preferences.maxMinutes) minutes")
                    .font(nunito(40, .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(Color.gsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                Slider(
                    value: Binding(
                        get: { Double(store.preferences.maxMinutes) },
                        set: { value in store.answerPreference(sound: false) { $0.maxMinutes = Int(value / 5).clamped(to: 3...12) * 5 } }
                    ),
                    in: 15...60,
                    step: 5
                )
                .tint(Color.gsPeach)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in adjustingSlider = true }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                adjustingSlider = false
                            }
                        }
                )
            }
            .stagger(3)
        case .servings:
            HStack(spacing: 12) {
                ForEach(Array([1, 2, 3, 4, 5, 6].enumerated()), id: \.element) { i, count in
                    Button {
                        store.answerPreference { $0.servings = count }
                    } label: {
                        Text("\(count)")
                            .font(nunito(18, .black))
                            .foregroundStyle(store.preferences.servings == count ? Color.white : Color.gsFg)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(store.preferences.servings == count ? Color.gsDock : Color.gsCard)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressableStyle(scale: 0.95))
                    .stagger(3 + i)
                }
            }
        case .skill:
            optionGrid(["Beginner", "Comfortable", "Confident"], selected: store.preferences.skill) { value in
                store.answerPreference { $0.skill = value }
            }
        }
    }

    private func optionGrid(_ values: [String], selected: String, action: @escaping (String) -> Void) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.element) { i, value in
                PreferenceOption(
                    emoji: Self.emoji(for: value),
                    title: value,
                    subtitle: subtitle(for: value),
                    selected: selected == value
                ) { action(value) }
                .stagger(3 + i)
            }
        }
    }

    /// Two-column emoji tiles (big emoji over a label), like the reference's diet step.
    private func emojiTileGrid(_ values: [String], selected: String,
                               action: @escaping (String) -> Void) -> some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.element) { i, value in
                let isSel = selected == value
                Button { action(value) } label: {
                    VStack(spacing: 8) {
                        Text(Self.emoji(for: value)).font(.system(size: 34))
                        Text(value)
                            .font(nunito(14.5, .extrabold))
                            .foregroundStyle(Color.gsFg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .background(isSel ? Color.gsPeachSoft : Color.gsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSel ? Color.gsPeach : Color.clear, lineWidth: 2))
                    .shadow(color: .black.opacity(isSel ? 0.08 : 0.04),
                            radius: isSel ? 14 : 8, y: 6)
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .stagger(3 + i)
            }
        }
    }

    /// Emoji for each option value — SF Symbols can't express food/diet variety, and the
    /// reference leans on emoji throughout.
    static func emoji(for value: String) -> String {
        switch value {
        case "Eat healthier": return "🥗"
        case "Save time": return "⚡️"
        case "Meal prep": return "🍱"
        case "Try new food": return "🌍"
        case "Anything": return "🍽️"
        case "Vegetarian": return "🥕"
        case "High protein": return "🍗"
        case "Low carb": return "🥑"
        case "Mediterranean": return "🫒"
        case "Beginner": return "🐣"
        case "Comfortable": return "🍳"
        case "Confident": return "🔥"
        case "Peanuts": return "🥜"
        case "Dairy": return "🥛"
        case "Shellfish": return "🦐"
        case "Gluten": return "🌾"
        case "Pork": return "🥓"
        default: return "🍴"
        }
    }

    private func subtitle(for value: String) -> String {
        switch value {
        case "Eat healthier": return "Fresh, balanced picks first"
        case "Save time": return "Quick recipes for busy nights"
        case "Meal prep": return "Make-ahead meals and leftovers"
        case "Try new food": return "More variety in your suggestions"
        case "Anything": return "Keep every cuisine open"
        case "Vegetarian": return "Favor meat-free recipes"
        case "High protein": return "Prioritize filling meals"
        case "Low carb": return "Lean into lighter carb counts"
        case "Mediterranean": return "Favor bright, fresh dishes"
        case "Beginner": return "Simple steps and fewer surprises"
        case "Comfortable": return "Balanced recipes, normal pacing"
        case "Confident": return "More adventurous picks are welcome"
        default: return ""
        }
    }

}

private struct PreferenceOption: View {
    let emoji: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Emoji sits in a soft tile, like the reference's activity rows.
                Text(emoji)
                    .font(.system(size: 22))
                    .frame(width: 46, height: 46)
                    .background(selected ? Color.white.opacity(0.7) : Color.gsFill)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(nunito(15.5, .extrabold))
                        .foregroundStyle(Color.gsFg)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.gsAccentInk)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(selected ? Color.gsPeachSoft : Color.gsCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? Color.gsPeach : Color.clear, lineWidth: 2)
            )
            .shadow(color: Color.black.opacity(selected ? 0.08 : 0.04), radius: selected ? 14 : 8, x: 0, y: 6)
        }
        .buttonStyle(PressableStyle(scale: 0.975))
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}


/// Slides a piece of a question in from the right, offset by its position, so a question
/// arrives line by line instead of all at once. Honours Reduce Motion.
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

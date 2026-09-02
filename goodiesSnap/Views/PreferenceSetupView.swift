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

                Spacer(minLength: 26)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.eyebrow.uppercased())
                            .font(nunito(11, .black))
                            .tracking(2.1)
                            .foregroundStyle(Color.gsAccentInk)
                            .stagger(0)

                        Text(step.title)
                            .font(nunito(31, .black))
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .stagger(1)

                        Text(step.subtitle)
                            .font(nunito(14, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .stagger(2)
                    }

                    content
                        .padding(.top, 24)
                }
                // Re-keying on the step is what gives each question its own entrance.
                .id(store.preferenceIndex)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: store.preferenceForward ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: store.preferenceForward ? .leading : .trailing)
                            .combined(with: .opacity)
                    )
                )

                Spacer(minLength: 28)

                progress
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 18)

                Button { store.preferenceNext(maxIndex: Step.allCases.count - 1) } label: {
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
    }

    private var topBar: some View {
        HStack {
            if store.preferenceIndex > 0 {
                Button { store.preferenceBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color.gsFg)
                        .frame(width: 40, height: 40)
                        .background(Color.gsFill)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 40, height: 40)
            }

            Spacer()

            Image("SplashLogo")
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()

            Button {
                store.askForAccount()
            } label: {
                Text("Skip")
                    .font(nunito(13, .bold))
                    .foregroundStyle(Color.gsMuted)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .goal:
            optionGrid(["Eat healthier", "Save time", "Meal prep", "Try new food"], selected: store.preferences.goal) { value in
                store.answerPreference { $0.goal = value }
            }
        case .diet:
            optionGrid(["Anything", "Vegetarian", "High protein", "Low carb", "Mediterranean"], selected: store.preferences.diet) { value in
                store.answerPreference { $0.diet = value }
            }
        case .avoid:
            VStack(spacing: 10) {
                ForEach(Array(["Peanuts", "Dairy", "Shellfish", "Gluten", "Pork"].enumerated()), id: \.element) { i, value in
                    PreferenceOption(
                        title: value,
                        subtitle: store.preferences.avoid.contains(value) ? "We will keep this out of top picks" : "Tap to avoid",
                        selected: store.preferences.avoid.contains(value),
                        system: store.preferences.avoid.contains(value) ? "checkmark.circle.fill" : "circle"
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
                    title: value,
                    subtitle: subtitle(for: value),
                    selected: selected == value,
                    system: selected == value ? "checkmark.circle.fill" : "circle"
                ) { action(value) }
                .stagger(3 + i)
            }
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

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases.indices, id: \.self) { i in
                Capsule()
                    .fill(i == store.preferenceIndex ? Color.gsPeach : Color.gsFill)
                    .frame(width: i == store.preferenceIndex ? 24 : 7, height: 7)
            }
        }
    }
}

private struct PreferenceOption: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let system: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: system)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(selected ? Color.gsAccentInk : Color.gsMuted)
                    .frame(width: 28)

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
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 66)
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

import SwiftUI

// Shared furniture for the onboarding flow. Every step is built from these so seventeen
// screens read as one continuous experience rather than seventeen designs.

/// Standard page frame: a kicker, a headline, a body, then whatever the step is about, with
/// the primary action pinned to the bottom where the thumb already is.
struct OBPage<Header: View, Content: View, Action: View>: View {
    var kicker: String = ""
    var title: String
    var subtitle: String = ""
    /// Full-bleed content above the padded block — a photographic header, normally. Kept
    /// outside the horizontal padding so the image can run edge to edge.
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header()

                    VStack(alignment: .leading, spacing: 0) {
                        if !kicker.isEmpty {
                            Text(kicker.uppercased())
                                .font(nunito(11, .extrabold))
                                .tracking(1.4)
                                .foregroundStyle(Color.gsBrandBottom)
                                .padding(.bottom, 10)
                        }
                        if !title.isEmpty {
                            Text(title)
                                .font(nunito(30, .black))
                                .tracking(-0.9)
                                .foregroundStyle(Color.gsFg)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(nunito(14.5, .semibold))
                                .foregroundStyle(Color.gsMuted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                        }
                        content()
                            .padding(.top, title.isEmpty && kicker.isEmpty ? 4 : 22)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 8) { action() }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }
}

extension OBPage where Header == EmptyView {
    init(kicker: String = "", title: String, subtitle: String = "",
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder action: @escaping () -> Action) {
        self.init(kicker: kicker, title: title, subtitle: subtitle,
                  header: { EmptyView() }, content: content, action: action)
    }
}

/// The flow's primary button.
struct OBPrimary: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.medium)
            action()
        } label: {
            Text(title)
                .font(nunito(16, .extrabold))
                .foregroundStyle(Color.gsFg)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(DarkButtonStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

/// The quieter second option, for "just save this" / "not now".
struct OBSecondary: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(title)
                .font(nunito(14.5, .bold))
                .foregroundStyle(Color.gsMuted)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// A large tappable choice — video vs photo, a store, a budget.
struct OBChoice: View {
    var icon: String
    var title: String
    var detail: String = ""
    var selected: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            HStack(alignment: .top, spacing: 15) {
                // A thin stroke glyph, not a filled tile on a coloured square. The tiles
                // read as a settings list; this reads as type.
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(selected ? Color.gsBrandBottom : Color.fg(0.45))
                    .frame(width: 26, height: 26)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(nunito(17, .extrabold))
                        .foregroundStyle(Color.gsFg)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(nunito(13, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(selected ? Color.gsBrandBottom : Color.fg(0.25))
                    .padding(.top, 5)
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Without this the Spacer between the text and the arrow is dead space: a tap
            // in the middle of the row hits nothing and the row looks broken.
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(selected ? Color.gsBrandBottom : Color.gsFg.opacity(0.09))
                    .frame(height: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A plain selectable row — used where an icon would have to be invented, like the list of
/// supermarkets. A made-up glyph next to a real brand name looks like a broken logo.
struct OBPlainChoice: View {
    var title: String
    var detail: String = ""
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(nunito(17, .extrabold))
                        .foregroundStyle(selected ? Color.gsFg : Color.fg(0.75))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Color.gsBrandBottom : Color.gsFg.opacity(0.18),
                                      lineWidth: selected ? 6.5 : 1.5)
                        .frame(width: 21, height: 21)
                }
            }
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.gsFg.opacity(0.08)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A compact selectable pill, for meal types and budgets.
struct OBPill: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.light)
            action()
        } label: {
            Text(title)
                .font(nunito(13.5, .extrabold))
                .foregroundStyle(selected ? .white : Color.gsFg)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(selected ? AnyShapeStyle(LinearGradient(
                        colors: [.gsBrandTop, .gsBrandBottom],
                        startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.gsFill))
                )
        }
        .buttonStyle(.plain)
    }
}

/// The narrated checklist used while real work happens. Lines above `stage` are done, the
/// line at `stage` is in progress, the rest are waiting.
struct OBChecklist: View {
    var lines: [String]
    var stage: Int
    /// Set on the gradient pages, where everything inverts to white.
    var onGradient: Bool = false

    private var doneColor: Color { onGradient ? .white : .gsBrandBottom }
    private var pendingColor: Color { onGradient ? .white.opacity(0.35) : .gsFg.opacity(0.18) }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                HStack(spacing: 13) {
                    ZStack {
                        if i < stage {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(doneColor)
                        } else if i == stage {
                            Circle()
                                .trim(from: 0, to: 0.3)
                                .stroke(doneColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 14, height: 14)
                                .modifier(OBSpin())
                        } else {
                            Circle()
                                .fill(pendingColor)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(width: 18, height: 18)

                    Text(line)
                        .font(nunito(15, .bold))
                        .foregroundStyle(onGradient
                                         ? .white.opacity(i <= stage ? 1 : 0.5)
                                         : Color.gsFg.opacity(i <= stage ? 1 : 0.4))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Continuous rotation that respects Reduce Motion.
private struct OBSpin: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false),
                       value: spinning)
            .onAppear { spinning = true }
    }
}

/// A headline number with a caption — the cost, the weekly total, the counts.
struct OBStat: View {
    var value: String
    var caption: String
    var emphasis: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(nunito(emphasis ? 34 : 22, .black))
                .tracking(-0.8)
                .foregroundStyle(Color.gsFg)
            Text(caption)
                .font(nunito(12.5, .semibold))
                .foregroundStyle(Color.gsMuted)
        }
    }
}

/// The disclosure that keeps every estimated number honest.
///
/// It is not decoration: these figures come from an offline average-price table, not from the
/// user's shop, and a cost the app presents as fact when it is a guess is the fastest way to
/// lose their trust the first time they get to the till.
struct OBEstimateNote: View {
    var store: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.gsMuted)
                .padding(.top, 1)
            Text(store.isEmpty
                 ? "Estimated from average grocery prices (\(IngredientPrices.asOf)). Connect a store for real shelf prices."
                 : "Estimated from average grocery prices (\(IngredientPrices.asOf)) — not \(store)'s live prices yet.")
                .font(nunito(11.5, .semibold))
                .foregroundStyle(Color.gsMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Top chrome for the flow: back where going back makes sense, progress, and skip.
struct OBTopBar: View {
    @EnvironmentObject var store: AppStore
    var onGradient: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if store.onboard.step != .start && !store.onboard.step.isWorking {
                Button { store.onboardBackStep() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(onGradient ? .white : Color.gsFg)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            OBProgress(step: store.onboard.step, onGradient: onGradient)

            // Not on the first screen: it already offers "Sign in", and two ways out of a
            // screen the user has not started yet is just noise.
            if !store.onboard.step.isWorking && store.onboard.step != .start {
                Button { store.skipOnboard() } label: {
                    Text("Skip")
                        .font(nunito(13.5, .bold))
                        .foregroundStyle(onGradient ? .white.opacity(0.8) : Color.gsMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .animation(AppStore.lateralAnimation, value: store.onboard.step)
    }
}

/// A thin progress rail. Shows how far through the flow the user is without numbering the
/// steps — seventeen of anything sounds like a form.
struct OBProgress: View {
    var step: AppStore.OnboardStep
    var onGradient: Bool = false

    private var fraction: Double {
        let total = Double(AppStore.OnboardStep.allCases.count - 1)
        return total <= 0 ? 0 : Double(step.rawValue) / total
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(onGradient ? Color.white.opacity(0.25) : Color.gsFill)
                Capsule()
                    .fill(onGradient
                          ? AnyShapeStyle(Color.white)
                          : AnyShapeStyle(LinearGradient(colors: [.gsBrandTop, .gsBrandBottom],
                                                         startPoint: .leading, endPoint: .trailing)))
                    .frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
        .frame(maxWidth: .infinity)
        .animation(AppStore.pushAnimation, value: step)
        .accessibilityHidden(true)
    }
}

/// One recipe as a wide card — used on the reveal, the week and the summary.
struct OBRecipeCard: View {
    @EnvironmentObject var store: AppStore
    var recipe: Recipe
    /// A short badge on the right — a day name, say. Kept to a couple of characters: anything
    /// longer wraps and squeezes the title.
    var trailing: String = ""
    /// A per-serving price. Sits on the meta line rather than in `trailing`, where
    /// "$6.82/serving" wrapped across two lines on every row.
    var priceNote: String = ""

    private var meta: String {
        let base = "\(recipe.totalMinutes) min · \(recipe.ingredients.count) ingredients"
        return priceNote.isEmpty ? base : base + " · " + priceNote
    }

    var body: some View {
        HStack(spacing: 13) {
            CoverImage(url: recipe.imageURL)
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(nunito(15.5, .extrabold))
                    .foregroundStyle(Color.gsFg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meta)
                    .font(nunito(12, .semibold))
                    .foregroundStyle(priceNote.isEmpty ? Color.gsMuted : Color.gsAccentInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)

            if !trailing.isEmpty {
                Text(trailing)
                    .font(nunito(14, .extrabold))
                    .foregroundStyle(Color.gsAccentInk)
                    .fixedSize()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.gsCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.gsFg.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

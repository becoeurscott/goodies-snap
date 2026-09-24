import SwiftUI

// Steps 6–9: the two questions worth asking, then the list and what it costs.
//
// The questions are here — not on a form at the start — because each one visibly changes the
// number on the next screen. That is the whole difference between a profile question and a
// functional one.

// MARK: - 6. How many people

struct OBServingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        OBPage(
            kicker: "So we get the amounts right",
            title: "How many are you cooking for?",
            subtitle: "This sets the portions and the cost per serving."
        ) {
            VStack(spacing: 26) {
                HStack(spacing: 26) {
                    stepper(-1, icon: "minus", enabled: store.onboard.servings > 1)
                    VStack(spacing: 2) {
                        Text("\(store.onboard.servings)")
                            .font(nunito(64, .black))
                            .tracking(-2)
                            .foregroundStyle(Color.gsFg)
                            .contentTransition(.numericText())
                        Text(store.onboard.servings == 1 ? "person" : "people")
                            .font(nunito(13, .bold))
                            .foregroundStyle(Color.gsMuted)
                    }
                    .frame(minWidth: 90)
                    stepper(1, icon: "plus", enabled: store.onboard.servings < 12)
                }
                .frame(maxWidth: .infinity)

                if let recipe = store.onboard.recipe {
                    Text("\(recipe.title) · \(store.onboard.servings) serving\(store.onboard.servings == 1 ? "" : "s")")
                        .font(nunito(13, .semibold))
                        .foregroundStyle(Color.gsMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        } action: {
            OBPrimary(title: "Continue") { store.onboardNextStep() }
        }
    }

    private func stepper(_ delta: Int, icon: String, enabled: Bool) -> some View {
        Button {
            Haptics.tap(.light)
            withAnimation(AppStore.stepAnimation) {
                store.onboardSetServings(store.onboard.servings + delta)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.gsBrandBottom)
                .frame(width: 52, height: 52)
                .background(Circle().strokeBorder(Color.gsFg.opacity(0.14), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

// MARK: - 7. Where you shop

struct OBStoreView: View {
    @EnvironmentObject var store: AppStore

    private let stores = ["Walmart", "Target", "Kroger", "Aldi", "Costco", "Somewhere else"]

    var body: some View {
        OBPage(
            kicker: "So the prices mean something",
            title: "Where do you\nusually shop?",
            subtitle: "We'll use this to price your list."
        ) {
            VStack(spacing: 0) {
                // Deliberately unbranded rows. These are other companies' marks; a
                // stand-in SF Symbol beside "Walmart" looks like a logo that failed to load.
                ForEach(stores, id: \.self) { name in
                    OBPlainChoice(title: name, selected: store.onboard.store == name) {
                        store.onboardSetStore(name)
                    }
                }

                // Said before the prices appear, not after — a user who finds out on the next
                // screen that the numbers are guesses has been misled, however briefly.
                OBEstimateNote()
                    .padding(.top, 18)
            }
        } action: {
            OBPrimary(title: "Build my shopping list",
                      enabled: !store.onboard.store.isEmpty) {
                store.onboardBuildList()
                store.onboardNextStep()
            }
        }
    }
}

// MARK: - 8. The list

struct OBListView: View {
    @EnvironmentObject var store: AppStore

    /// Just this recipe's lines, grouped by aisle, so the list reads the way a shop walks.
    private var groups: [(aisle: String, items: [ShoppingItem])] {
        let mine = store.shopping.filter { $0.recipeID == store.onboard.recipe?.id }
        return Aisle.order.compactMap { aisle in
            let items = mine.filter { ($0.category.isEmpty ? Aisle.guess(for: $0.name) : $0.category) == aisle }
            return items.isEmpty ? nil : (aisle, items)
        }
    }

    private var owned: Int { store.shopping.filter { $0.recipeID == store.onboard.recipe?.id && $0.alreadyHave }.count }

    var body: some View {
        OBPage(
            kicker: "Your shopping list",
            title: "Everything you need,\nin one list",
            subtitle: "Tap anything you already have at home — it comes straight off the total."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groups, id: \.aisle) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.aisle.uppercased())
                            .font(nunito(11, .extrabold))
                            .tracking(1.2)
                            .foregroundStyle(Color.gsMuted)
                        ForEach(group.items, id: \.id) { item in
                            row(item)
                        }
                    }
                }

                if let total = store.onboardRecipeCost {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider().overlay(Color.gsFg.opacity(0.1))
                        HStack(alignment: .firstTextBaseline) {
                            OBStat(value: store.formatPrice(total.cents),
                                   caption: owned > 0
                                       ? "estimated total · \(owned) item\(owned == 1 ? "" : "s") you already have"
                                       : "estimated total for \(store.onboard.servings) serving\(store.onboard.servings == 1 ? "" : "s")",
                                   emphasis: true)
                            Spacer()
                        }
                        .contentTransition(.numericText())
                        OBEstimateNote(store: store.onboard.store)
                    }
                }
            }
        } action: {
            OBPrimary(title: "See the cost breakdown  →") { store.onboardNextStep() }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            store.toggleAlreadyHave(item.id)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.alreadyHave ? "checkmark.square.fill" : "square")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.alreadyHave ? Color.gsBrandBottom : Color.gsFg.opacity(0.22))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(nunito(14, .bold))
                        .foregroundStyle(item.alreadyHave ? Color.gsMuted : Color.gsFg)
                        .strikethrough(item.alreadyHave, color: Color.gsMuted)
                        .multilineTextAlignment(.leading)
                    if !item.qty.isEmpty {
                        Text(item.qty)
                            .font(nunito(11.5, .semibold))
                            .foregroundStyle(Color.gsMuted)
                    }
                }
                Spacer(minLength: 8)

                if let price = store.price(for: item) {
                    Text(store.formatPrice(price.cents))
                        .font(nunito(13.5, .extrabold))
                        .foregroundStyle(item.alreadyHave ? Color.gsMuted.opacity(0.6) : Color.gsFg)
                        .strikethrough(item.alreadyHave, color: Color.gsMuted)
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(item.alreadyHave ? "already have" : "on the list")")
    }
}

// MARK: - 9. The cost

struct OBCostView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        OBPage(
            kicker: "Here's the useful bit",
            title: "What this meal\nactually costs",
            subtitle: store.onboard.store.isEmpty
                ? "Based on average grocery prices."
                : "Based on average prices for a shop like \(store.onboard.store)."
        ) {
            VStack(alignment: .leading, spacing: 24) {
                if let perServing = store.onboardPerServing, let total = store.onboardRecipeCost {
                    HStack(spacing: 0) {
                        OBStat(value: store.formatPrice(perServing.cents),
                               caption: "per serving", emphasis: true)
                        Spacer()
                        OBStat(value: store.formatPrice(total.cents),
                               caption: "all \(store.onboard.servings) serving\(store.onboard.servings == 1 ? "" : "s")")
                    }

                    comparison(perServing.cents)
                }

                let swaps = store.onboardSwaps
                if !swaps.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        Text("Want to make it cheaper?")
                            .font(nunito(16, .extrabold))
                            .foregroundStyle(Color.gsFg)
                        Text(swaps.count == 1
                             ? "One swap that cooks the same way:"
                             : "\(swaps.count) swaps that cook the same way:")
                            .font(nunito(12.5, .semibold))
                            .foregroundStyle(Color.gsMuted)

                        ForEach(swaps, id: \.from) { swap in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(swap.from.capitalized)
                                        .font(nunito(14, .bold))
                                        .foregroundStyle(Color.gsFg)
                                    Text("try \(swap.to)")
                                        .font(nunito(12, .semibold))
                                        .foregroundStyle(Color.gsMuted)
                                }
                                Spacer(minLength: 8)
                                HStack(spacing: 6) {
                                    Text(store.formatPrice(swap.fromCents))
                                        .font(nunito(12.5, .semibold))
                                        .foregroundStyle(Color.gsMuted)
                                        .strikethrough()
                                    Text(store.formatPrice(swap.toCents))
                                        .font(nunito(14, .extrabold))
                                        .foregroundStyle(Color.gsBrandBottom)
                                }
                            }
                            .padding(.vertical, 13)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.gsFg.opacity(0.08)).frame(height: 1)
                            }
                        }
                    }
                }

                OBEstimateNote(store: store.onboard.store)
            }
        } action: {
            OBPrimary(title: "Plan the rest of my week  →") { store.onboardNextStep() }
            OBSecondary(title: "Just save this recipe") { store.skipOnboard() }
        }
    }

    /// One honest sentence of context. No made-up takeaway averages — just the arithmetic the
    /// user can check against the number above it.
    private func comparison(_ perServing: Int) -> some View {
        let weekly = perServing * 7
        return VStack(alignment: .leading, spacing: 5) {
            Text("A WEEK AT THIS PRICE")
                .font(nunito(10.5, .extrabold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.75))
            Text("About \(store.formatPrice(weekly)) a person")
                .font(nunito(22, .black))
                .tracking(-0.5)
                .foregroundStyle(.white)
            Text("for seven dinners like this one")
                .font(nunito(13, .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [.gsBrandTop, .gsBrandBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }
}

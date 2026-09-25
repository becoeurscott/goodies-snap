import SwiftUI

// Steps 10–13: "you've got dinner sorted — want the rest of the week?"
//
// This is the transition the flow has been earning. The user has a recipe, a list and a
// number; extending that to seven days is an obvious next step rather than a new pitch.

// MARK: - 10. The offer

struct OBPlanPromptView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        OBHeroPage(
            kicker: "Dinner's sorted",
            title: "Want the rest\nof your week?",
            subtitle: "We'll build it around what you just saved, reusing ingredients so you buy less."
        ) {
            if let recipe = store.onboard.recipe {
                HStack(spacing: 14) {
                    CoverImage(url: recipe.imageURL)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MONDAY")
                            .font(nunito(10, .extrabold))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(recipe.title)
                            .font(nunito(16, .extrabold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(0.16))
                )
            }
        } action: {
            OBLightPrimary(title: "Build my week") { store.onboardNextStep() }
            OBLightSecondary(title: "Just save this recipe") { store.skipOnboard() }
        }
    }
}

// MARK: - 11. Setup

struct OBPlanSetupView: View {
    @EnvironmentObject var store: AppStore

    private let mealOptions = ["Breakfast", "Lunch", "Dinner"]
    private let budgets = ["Under $50", "$50–75", "$75–100", "$100+"]

    var body: some View {
        OBPage(
            kicker: "Two quick things",
            title: "Let's plan your week",
            subtitle: "We already know it's \(store.onboard.servings) \(store.onboard.servings == 1 ? "person" : "people") — no need to ask again."
        ) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Which meals should we plan?")
                        .font(nunito(15.5, .extrabold))
                        .foregroundStyle(Color.gsFg)
                    HStack(spacing: 9) {
                        ForEach(mealOptions, id: \.self) { meal in
                            OBPill(title: meal, selected: store.onboard.meals.contains(meal)) {
                                if store.onboard.meals.contains(meal) {
                                    // Never leave the plan with nothing to build.
                                    if store.onboard.meals.count > 1 { store.onboard.meals.remove(meal) }
                                } else {
                                    store.onboard.meals.insert(meal)
                                }
                            }
                        }
                    }
                    if store.onboard.meals != ["Dinner"] {
                        Text("We'll start with dinners this week and add the rest as you go.")
                            .font(nunito(12, .semibold))
                            .foregroundStyle(Color.gsMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("Weekly food budget")
                        .font(nunito(15.5, .extrabold))
                        .foregroundStyle(Color.gsFg)
                    Text("Optional — it just tells us how hard to push on cost.")
                        .font(nunito(12, .semibold))
                        .foregroundStyle(Color.gsMuted)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(budgets, id: \.self) { budget in
                            OBPill(title: budget, selected: store.onboard.budget == budget) {
                                store.onboard.budget = store.onboard.budget == budget ? "" : budget
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 11) {
                    Text("How many dinners?")
                        .font(nunito(15.5, .extrabold))
                        .foregroundStyle(Color.gsFg)
                    HStack(spacing: 9) {
                        ForEach([3, 5, 7], id: \.self) { n in
                            OBPill(title: "\(n)", selected: store.onboard.dinnersWanted == n) {
                                store.onboard.dinnersWanted = n
                            }
                        }
                    }
                }
            }
        } action: {
            OBPrimary(title: "Build my week") { store.onboardBuildWeek() }
        }
    }
}

// MARK: - 12. Building

struct OBPlanBuildingView: View {
    @EnvironmentObject var store: AppStore

    private var lines: [String] {
        [
            "Kept \(store.onboard.recipe?.title ?? "your recipe")",
            "Matched dishes to your taste",
            "Reused ingredients where we could",
            "Priced the whole shop",
            "Finalising your week",
        ]
    }

    var body: some View {
        // The router paints the gradient; this screen is only its contents.
        VStack(spacing: 0) {
            Spacer()

            OBWorkingRing()

            Text("Building your week")
                .font(nunito(28, .black))
                .tracking(-0.8)
                .foregroundStyle(.white)
                .padding(.top, 26)

            OBChecklist(lines: lines, stage: store.onboard.weekStage, onGradient: true)
                .frame(maxWidth: 300)
                .padding(.top, 32)

            Spacer()
        }
        .padding(.horizontal, 26)
    }
}

// MARK: - 13. The week

struct OBWeekView: View {
    @EnvironmentObject var store: AppStore

    private var days: [String] { Array(AppStore.days.prefix(store.onboard.plannedWeek.count)) }

    var body: some View {
        OBPage(
            kicker: "Your week is ready",
            title: "\(store.onboard.plannedWeek.count) dinners,\none shopping list",
            subtitle: "Built around the recipe you brought in."
        ) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 9) {
                    ForEach(Array(zip(days, store.onboard.plannedWeek)), id: \.1.id) { day, recipe in
                        HStack(spacing: 12) {
                            Text(day.prefix(3).uppercased())
                                .font(nunito(11, .extrabold))
                                .tracking(0.8)
                                .foregroundStyle(Color.gsMuted)
                                .frame(width: 34, alignment: .leading)
                            // Per serving, and labelled as such: the total below is the whole
                            // week's shop, so an unlabelled column of numbers invites the user
                            // to add them up and get a figure that doesn't reconcile.
                            OBRecipeCard(
                                recipe: recipe,
                                priceNote: store.costPerServing(recipe)
                                    .map { "\(store.formatPrice($0.cents))/serving" } ?? "")
                        }
                    }
                }

                if let week = store.onboardWeekCost {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider().overlay(Color.gsFg.opacity(0.1))
                        OBStat(value: store.formatPrice(week.cents),
                               caption: "estimated for the whole week's shop",
                               emphasis: true)

                        if store.onboard.weekSharedCount > 0 {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(store.onboard.weekSharedCount) shared ingredient\(store.onboard.weekSharedCount == 1 ? "" : "s")")
                                    .font(nunito(20, .black))
                                    .tracking(-0.4)
                                    .foregroundStyle(.white)
                                Text("Bought once, used across the week.")
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

                        OBEstimateNote(store: store.onboard.store)
                    }
                }
            }
        } action: {
            OBPrimary(title: "Add it all to my list  →") {
                store.onboardShopTheWeek()
                store.onboardNextStep()
            }
            OBSecondary(title: "Not right now") { store.onboardNextStep() }
        }
    }
}

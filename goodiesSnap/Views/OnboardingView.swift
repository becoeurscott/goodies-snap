import SwiftUI

/// The value-first onboarding flow.
///
/// One phase, seventeen steps (see `AppStore.OnboardStep`). The router is deliberately thin:
/// the steps own their own layout, and everything they share lives in `OnboardKit`.
struct OnboardingView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ZStack {
            if store.onboard.step.usesGradient {
                OBGradient().ignoresSafeArea()
            } else {
                Color.gsBg.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // The opening screen is full-bleed artwork; a progress rail over the logo
                // would fight it.
                if store.onboard.step != .start {
                    OBTopBar(onGradient: store.onboard.step.usesGradient)
                }
                step
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .move(edge: store.onboard.forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: store.onboard.forward ? .leading : .trailing).combined(with: .opacity)
                    ))
                    .id(store.onboard.step)
            }
        }
        .foregroundStyle(Color.gsFg)
        // The narration timers hold a reference to the store; a step left early must not
        // keep ticking and advance a screen the user has already walked away from.
        .onDisappear { store.onboard.narrationTask?.cancel() }
    }

    @ViewBuilder
    private var step: some View {
        switch store.onboard.step {
        case .start:        OBStartView()
        case .source:       OBSourceView()
        case .paste:        OBPasteView()
        case .extracting:   OBExtractingView()
        case .recipe:       OBRecipeRevealView()
        case .servings:     OBServingsView()
        case .store:        OBStoreView()
        case .list:         OBListView()
        case .cost:         OBCostView()
        case .planPrompt:   OBPlanPromptView()
        case .planSetup:    OBPlanSetupView()
        case .planBuilding: OBPlanBuildingView()
        case .week:         OBWeekView()
        case .valueSummary: OBValueSummaryView()
        case .community:    OBCommunityView()
        case .foodSystem:   OBFoodSystemView()
        case .snapTeaser:   OBSnapTeaserView()
        }
    }
}
